//
//  kernel_u.m
//  reton
//
//  Created by Luca on 18.02.21.
//

#import <Foundation/Foundation.h>
#include "../Misc/support.h"
#include "../Exploit/cicuta_virosa.h"

kptr_t get_proc_struct_for_pid(pid_t pid){
    __block kptr_t proc = KPTR_NULL;
    void (^handler)(kptr_t, pid_t, bool *) = ^(kptr_t found_proc, pid_t found_pid, bool *iterate) {
        if (found_pid == pid) {
            proc = found_proc;
            *iterate = false;
        }
    };
    // TODO check if possible (allproc inclusive?)
    return proc;
}


bool set_platform_binary(kptr_t proc, bool set) {
    bool ret = false;
    if(!KERN_POINTER_VALID(proc)) return 0;
    kptr_t task_struct_addr = read_64(proc + 0x10);
    if(!KERN_POINTER_VALID(task_struct_addr)) return 0;
    kptr_t task_t_flags_addr = task_struct_addr + 0x3a0;
    uint32_t task_t_flags = read_32(task_t_flags_addr);
    if (set) {
        task_t_flags |= TF_PLATFORM;
    } else {
        task_t_flags &= ~(TF_PLATFORM);
    }
    write_32((task_struct_addr + 0x3a0), (void*)task_t_flags);
    ret = true;
out:;
    return ret;
}
