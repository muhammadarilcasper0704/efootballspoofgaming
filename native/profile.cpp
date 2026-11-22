#include <sys/types.h>
#include "zygisk.hpp"
#include <dobby.h>
#include <android/log.h>
// The two Android GLES entry libraries can export the same or different stubs.
#include <GLES3/gl3.h>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>
#include <sys/system_properties.h>

#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/mount.h>
#include <unistd.h>

namespace {
constexpr char target[] = "jp.konami.pesam";
constexpr char tag[] = "ArilEFO";
void report(const char* msg) { __android_log_write(ANDROID_LOG_INFO, tag, msg); }

struct Options { bool device{}, cpu{}, gpu{}; };
constexpr char profileDir[]="/data/adb/modules/aril_efo_personal";
bool readSelection(int dir, char (&bits)[4]) {
    char raw[5]{};
    int fd=openat(dir,"selection",O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if(fd<0)return false;
    ssize_t size=read(fd,raw,sizeof(raw));
    close(fd);
    if(size!=3 && !(size==4 && raw[3]=='\n'))return false;
    for(int i=0;i<3;++i)if(raw[i]!='0' && raw[i]!='1')return false;
    memcpy(bits,raw,3);
    return true;
}
// The companion can only return three flags from this module's fixed path.
void companion(int socket) {
    char bits[4]="---";
    int dir=open(profileDir,O_RDONLY|O_DIRECTORY|O_CLOEXEC|O_NOFOLLOW);
    if(dir>=0){readSelection(dir,bits);close(dir);}
    send(socket,bits,3,MSG_NOSIGNAL);
}
int auditFd=-1;
void mark(int offset,char value) {
    if(auditFd>=0)pwrite(auditFd,&value,1,offset);
}
void beginAudit(const Options& flags) {
    auditFd=syscall(__NR_memfd_create,"aril-efo-061",1U);
    if(auditFd<0)return;
    char data[]="000-----";
    data[0]=flags.device?'1':'0';data[1]=flags.cpu?'1':'0';data[2]=flags.gpu?'1':'0';
    if(write(auditFd,data,8)!=8){close(auditFd);auditFd=-1;}
}
bool mountCpu(int dir) {
    // Prefer the packaged file. A private memory file also works when the
    // Zygote domain cannot traverse the module directory.
    int fd=dir<0?-1:openat(dir,"cpuinfo",O_RDONLY|O_CLOEXEC|O_NOFOLLOW);
    if(fd<0){
        static constexpr char cpu[]=R"CPU(processor	: 0
model name	: Apple A8 (Typhoon)
CPU architecture: 8

processor	: 1
model name	: Apple A8 (Typhoon)
CPU architecture: 8

Hardware	: Apple A8
)CPU";
        fd=syscall(__NR_memfd_create,"aril-cpuinfo",1U);
        if(fd<0)return false;
        if(write(fd,cpu,sizeof(cpu)-1)!=sizeof(cpu)-1){close(fd);return false;}
    }
    char path[64]; snprintf(path,sizeof path,"/proc/self/fd/%d",fd);
    bool ok=unshare(CLONE_NEWNS)==0 && mount(nullptr,"/",nullptr,MS_REC|MS_PRIVATE,nullptr)==0
        && mount(path,"/proc/cpuinfo",nullptr,MS_BIND,nullptr)==0;
    int error=errno;
    close(fd);
    if(!ok)__android_log_print(ANDROID_LOG_WARN,tag,"CPU: mount errno=%d",error);
    return ok;
}

bool verifyCpu() {
    FILE* f=fopen("/proc/cpuinfo","r");
    if (!f) return false;
    char line[256]; unsigned cores=0; bool model=false;
    while (fgets(line,sizeof line,f)) {
        if (strncmp(line,"processor\t:",11)==0) ++cores;
        if (strstr(line,"Apple A8")) model=true;
    }
    fclose(f);
    return cores==2 && model;
}

bool setBuild(JNIEnv* env,bool soc) {
    jclass build=env->FindClass("android/os/Build");
    if (!build) {env->ExceptionClear(); return false;}
    const char* fields[][2]={
        {"MODEL","iPhone 6"},{"BRAND","Apple"},{"MANUFACTURER","Apple"},
        {"DEVICE","iPhone7,2"},{"BOARD","N61AP"},{"PRODUCT","iPhone7,2"},{"HARDWARE","t7000"},
        {"SOC_MODEL","Apple A8"},{"SOC_MANUFACTURER","Apple"}};
    bool all=true;
    for (const auto& pair:fields) {
        if((strncmp(pair[0],"SOC_",4)==0)!=soc)continue;
        jfieldID field=env->GetStaticFieldID(build,pair[0],"Ljava/lang/String;");
        if (!field) {env->ExceptionClear();all=false;continue;}
        jstring s=env->NewStringUTF(pair[1]);
        if (!s) {env->ExceptionClear();all=false;break;}
        env->SetStaticObjectField(build,field,s);
        if(env->ExceptionCheck()){env->ExceptionClear();all=false;}
        else {
            jobject actual=env->GetStaticObjectField(build,field);
            if(env->ExceptionCheck()){env->ExceptionClear();all=false;}
            else if(!env->IsSameObject(s,actual)) all=false;
            if(actual) env->DeleteLocalRef(actual);
        }
        env->DeleteLocalRef(s);
    }
    env->DeleteLocalRef(build);
    return all;
}

struct ExtensionList {
    std::vector<std::string> names;
    std::string joined;
    explicit ExtensionList(const char* raw) {
        // Keep portable extensions supplied by this GL context. Vendor-specific
        // features are only meaningful with the corresponding implementation.
        std::istringstream input(raw);
        std::string word;
        while(input >> word) {
            if(word.rfind("GL_OES_", 0) != 0 && word.rfind("GL_EXT_", 0) != 0 &&
               word.rfind("GL_KHR_", 0) != 0 && word.rfind("GL_APPLE_", 0) != 0) continue;
            if(!joined.empty())joined+=' ';
            joined+=word;
            names.push_back(word);
        }
    }
};
using Query=const GLubyte*(*)(GLenum);
using Indexed=const GLubyte*(*)(GLenum,GLuint);
using Integer=void(*)(GLenum,GLint*);
struct ApiSlot { Query query{}; Indexed indexed{}; Integer integer{}; };
ApiSlot slots[2]{};
std::atomic<bool> gpuReady{false};
std::atomic_flag rendererSeen=ATOMIC_FLAG_INIT,extensionsSeen=ATOMIC_FLAG_INIT;
const ExtensionList* extensions(Query query) {
    auto raw=reinterpret_cast<const char*>(query(GL_EXTENSIONS));
    if(!raw)return nullptr;
    static std::mutex mutex;
    static std::map<std::string,ExtensionList> lists;
    std::lock_guard<std::mutex> guard(mutex);
    auto it=lists.find(raw);
    if(it==lists.end())it=lists.emplace(raw,ExtensionList(raw)).first;
    if(!extensionsSeen.test_and_set()){
        mark(7,'1');
        __android_log_print(ANDROID_LOG_INFO,tag,"GLES: kueri ekstensi teramati; %zu token dilaporkan.",it->second.names.size());
        __android_log_print(ANDROID_LOG_INFO,tag,"GL_EXTENSIONS: %s",it->second.joined.c_str());
    }
    return &it->second;
}
const GLubyte* bytes(const char* s){return reinterpret_cast<const GLubyte*>(s);}
template<int N> const GLubyte* gpuString(GLenum name){
    Query query=slots[N].query;
    if(!query)return nullptr;
    const GLubyte* real=query(name);
    if(!real||!gpuReady.load())return real;
    switch(name){
        case GL_RENDERER:
            if(!rendererSeen.test_and_set()){mark(6,'1');report("GLES: panggilan GL_RENDERER teramati; mengembalikan Apple A8 GPU.");}
            return bytes("Apple A8 GPU");
        case GL_VENDOR:return bytes("Apple Inc.");
        // Preserve the active context's API and shader language to keep ES3 games compatible.
        case GL_EXTENSIONS:{auto list=extensions(query);return list?bytes(list->joined.c_str()):real;}
        default:return real;
    }
}
template<int N> void gpuInteger(GLenum name,GLint* result){
    auto& api=slots[N];
    if(!api.integer)return;
    api.integer(name,result);
    if(!result || !gpuReady.load())return;
    if(name!=GL_NUM_EXTENSIONS)return;
    auto version=reinterpret_cast<const char*>(api.query(GL_VERSION));
    int major=0,minor=0;
    if(!version||sscanf(version,"OpenGL ES %d.%d",&major,&minor)!=2||major!=3)return;
    auto list=extensions(api.query);
    if(list)*result=static_cast<GLint>(list->names.size());
}
template<int N> const GLubyte* gpuIndexed(GLenum name,GLuint i){
    auto& api=slots[N];
    if(!api.indexed)return nullptr;
    if(!gpuReady.load()||name!=GL_EXTENSIONS)return api.indexed(name,i);
    const char* v=reinterpret_cast<const char*>(api.query(GL_VERSION));
    if(!v || strncmp(v,"OpenGL ES 3.",12)!=0)return api.indexed(name,i);
    auto list=extensions(api.query);
    if(!list)return api.indexed(name,i);
    if(i>=list->names.size())return api.indexed(name,~GLuint(0));
    return bytes(list->names[i].c_str());
}
template<typename T> bool attach(void* addr,T replacement,T& original){
    return addr && DobbyHook(addr,reinterpret_cast<dobby_dummy_func_t>(replacement),
            reinterpret_cast<dobby_dummy_func_t*>(&original))==0;
}
void enableGPU(){
    void* lib[2]={dlopen("libGLESv2.so",RTLD_NOW|RTLD_LOCAL),dlopen("libGLESv3.so",RTLD_NOW|RTLD_LOCAL)};
    if(!lib[0]||!lib[1]){report("GLES: loader ES2/ES3 tidak lengkap.");return;}
    void* q[2],*n[2],*idx[2];
    for(int i=0;i<2;i++){q[i]=dlsym(lib[i],"glGetString");n[i]=dlsym(lib[i],"glGetIntegerv");idx[i]=dlsym(lib[i],"glGetStringi");}
    if(!q[0]||!q[1]||!n[0]||!n[1]||!idx[1]){report("GLES: ekspor kueri belum lengkap.");return;}
    bool ok=attach(q[0],gpuString<0>,slots[0].query);
    if(q[0]==q[1])slots[1].query=slots[0].query;
    else ok=ok&&attach(q[1],gpuString<1>,slots[1].query);
    ok=ok&&attach(n[0],gpuInteger<0>,slots[0].integer);
    if(n[0]==n[1])slots[1].integer=slots[0].integer;
    else ok=ok&&attach(n[1],gpuInteger<1>,slots[1].integer);
    ok=ok&&attach(idx[1],gpuIndexed<1>,slots[1].indexed);
    if(idx[0]==idx[1])slots[0].indexed=slots[1].indexed;
    else if(idx[0])ok=ok&&attach(idx[0],gpuIndexed<0>,slots[0].indexed);
    gpuReady.store(ok);
    report(ok?"GLES: profil tersedia; menunggu kueri game.":"GLES: pemasangan tidak lengkap; kueri memakai hasil driver.");
}
using PropertyGet=int(*)(const char*,char*);
PropertyGet systemGet=nullptr;
bool deviceProps=false,socProps=false;
int profileProperty(const char* key,char* out){
    if(!key||!out||!systemGet)return 0;
    struct Field {const char* key;const char* value;};
    static constexpr Field deviceFields[]={
        {"ro.product.manufacturer","Apple"},{"ro.product.model","iPhone 6"},
        {"ro.product.brand","Apple"},{"ro.product.board","N61AP"},{"ro.product.name","iPhone7,2"},{"ro.hardware","t7000"},
        {"ro.product.device","iPhone7,2"},{"ro.board.platform","t7000"}
    };
    static constexpr Field cpuFields[]={{"ro.soc.model","Apple A8"},{"ro.soc.manufacturer","Apple"}};
    if(deviceProps)for(auto& f:deviceFields)if(strcmp(key,f.key)==0){strcpy(out,f.value);return strlen(f.value);}
    if(socProps)for(auto& f:cpuFields)if(strcmp(key,f.key)==0){strcpy(out,f.value);return strlen(f.value);}
    return systemGet(key,out);
}
void enableProperties(bool device,bool cpu){
    deviceProps=device;socProps=cpu;
    const bool ok=attach(dlsym(RTLD_DEFAULT,"__system_property_get"),profileProperty,systemGet);
    report(ok?"Properti: getter langsung siap di proses game.":"Properti: getter langsung tidak tersedia.");
}

class Personal final:public zygisk::ModuleBase {
    zygisk::Api* api{};
    JNIEnv* env{};
    Options flags{};
    bool selected{};
public:
    void onLoad(zygisk::Api* a,JNIEnv* e) override {api=a;env=e;}
    void preServerSpecialize(zygisk::ServerSpecializeArgs*) override {api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);}
    void preAppSpecialize(zygisk::AppSpecializeArgs* args) override {
        if(args->nice_name){
            const char* s=env->GetStringUTFChars(args->nice_name,nullptr);
            if(s){selected=strcmp(s,target)==0;env->ReleaseStringUTFChars(args->nice_name,s);}
            else env->ExceptionClear();
        }
        if(!selected){api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);return;}
        int dir=api->getModuleDir();
        char bits[4]{};
        bool valid=dir>=0 && readSelection(dir,bits);
        if(!valid){
            int sock=api->connectCompanion();
            if(sock>=0){
                valid=recv(sock,bits,3,MSG_WAITALL)==3 && strspn(bits,"01")==3;
                close(sock);
            }
        }
        if(valid)flags={bits[0]=='1',bits[1]=='1',bits[2]=='1'};
        else report("Konfigurasi: pembacaan langsung dan melalui companion gagal.");
        if(flags.cpu&&!mountCpu(dir))report("CPU: pemasangan cpuinfo gagal.");
        if(dir>=0)close(dir);
        if(!flags.gpu&&!flags.device&&!flags.cpu)api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
        if(!selected||(!flags.device&&!flags.cpu&&!flags.gpu))return;
        beginAudit(flags);
        if(flags.device||flags.cpu)enableProperties(flags.device,flags.cpu);
        if(flags.cpu)report(setBuild(env,true)?"CPU: Apple A8 terbaca kembali di Java.":"CPU: model SoC Java belum lengkap.");
        if(flags.device){bool ok=setBuild(env,false);mark(3,ok?'1':'0');report(ok?"Device: field Java Build terbaca kembali (iPhone 6).":"Device: sebagian field Java Build gagal.");}
        if(flags.cpu){bool ok=verifyCpu();mark(4,ok?'1':'0');report(ok?"CPU: Apple A8 dua inti terbaca sesudah spesialisasi.":"CPU: profil belum terbaca.");}
        if(flags.gpu){enableGPU();mark(5,gpuReady.load()?'1':'0');}
    }
};
}
REGISTER_ZYGISK_MODULE(Personal)

REGISTER_ZYGISK_COMPANION(companion)
