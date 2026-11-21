#include "zygisk.hpp"
#include <dobby.h>
#include <android/log.h>
#include <GLES2/gl2.h>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/mount.h>
#include <unistd.h>

namespace {
constexpr char target[] = "jp.konami.pesam";
constexpr char tag[] = "ArilEFO";
void report(const char* msg) { __android_log_write(ANDROID_LOG_INFO, tag, msg); }

struct Options { bool device{}, cpu{}, gpu{}; };
Options loadOptions(int dir) {
    char b[8]{};
    int f = openat(dir, "selection", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (f < 0) return {};
    ssize_t n = read(f, b, sizeof b);
    close(f);
    if ((n != 3 && !(n == 4 && b[3] == '\n')) || strspn(b, "01") != 3) return {};
    return {b[0]=='1', b[1]=='1', b[2]=='1'};
}

bool mountCpu(int dir) {
    int fd = openat(dir,"cpuinfo",O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return false;
    char path[64]; snprintf(path,sizeof path,"/proc/self/fd/%d",fd);
    bool ok = unshare(CLONE_NEWNS) == 0
        && mount(nullptr,"/",nullptr,MS_REC | MS_PRIVATE,nullptr) == 0
        && mount(path,"/proc/cpuinfo",nullptr,MS_BIND,nullptr) == 0;
    close(fd);
    return ok;
}

bool verifyCpu() {
    FILE* f=fopen("/proc/cpuinfo","r");
    if (!f) return false;
    char line[256]; unsigned cores=0; bool model=false;
    while (fgets(line,sizeof line,f)) {
        if (strncmp(line,"processor\t:",11)==0) ++cores;
        if (strstr(line,"MT6737T")) model=true;
    }
    fclose(f);
    return cores==4 && model;
}

bool setBuild(JNIEnv* env) {
    jclass build=env->FindClass("android/os/Build");
    if (!build) {env->ExceptionClear(); return false;}
    const char* fields[][2]={
        {"MODEL","SM-G532G"},{"BRAND","samsung"},{"MANUFACTURER","samsung"},
        {"DEVICE","grandpplte"},{"PRODUCT","grandppltedx"},{"BOARD","MT6737T"},
        {"SOC_MODEL","MT6737T"},{"SOC_MANUFACTURER","MediaTek"},
        {"FINGERPRINT","samsung/grandppltedx/grandpplte:6.0.1/MMB29T/G532GDXU1ASA5:user/release-keys"}};
    bool all=true;
    for (const auto& pair:fields) {
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

using Query=const GLubyte* (*)(GLenum);
Query original=nullptr;
std::atomic_flag firstRenderer=ATOMIC_FLAG_INIT;
const GLubyte* profileString(GLenum name){
    if(!original)return nullptr;
    const GLubyte* real=original(name);
    if (!real)return nullptr;
    if (name==GL_RENDERER){
        if(!firstRenderer.test_and_set()) report("GLES: panggilan GL_RENDERER teramati; mengembalikan Mali-T720.");
        return reinterpret_cast<const GLubyte*>("Mali-T720");
    }
    if(name==GL_VENDOR)return reinterpret_cast<const GLubyte*>("ARM");
    return real;
}
void enableGPU(){
    // Keep the loader reference while the replacement is installed.
    void* lib=dlopen("libGLESv2.so",RTLD_NOW | RTLD_LOCAL);
    if (!lib){report("GLES: loader tidak tersedia.");return;}
    void* fn=dlsym(lib,"glGetString");
    if (!fn || DobbyHook(fn,reinterpret_cast<void*>(profileString),reinterpret_cast<void**>(&original))!=0){
        dlclose(lib);report("GLES: pemasangan gagal.");return;
    }
    report("GLES: menunggu panggilan GL_RENDERER.");
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
        if(dir>=0){
            flags=loadOptions(dir);
            if(flags.cpu&&!mountCpu(dir)) report("CPU: pemasangan cpuinfo gagal.");
            close(dir);
        }
        if(!flags.gpu)api->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
    }
    void postAppSpecialize(const zygisk::AppSpecializeArgs*) override {
        if(!selected)return;
        if(flags.device) report(setBuild(env)?"Device: field Java Build terbaca kembali.":"Device: sebagian field Java Build gagal.");
        if(flags.cpu) report(verifyCpu()?"CPU: profil empat inti terbaca sesudah spesialisasi.":"CPU: profil belum terbaca.");
        if(flags.gpu)enableGPU();
    }
};
}
REGISTER_ZYGISK_MODULE(Personal)
