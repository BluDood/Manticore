//
//  rootfs.h
//  reton
//
//  Created by Luca on 18.02.21.
//

#ifndef rootfs_h
#define rootfs_h

#include "util/kutils.h"

void start_rootfs_remount(void);
int remount_rootfs(kptr_t proc);
bool check_root_rw(void);
#endif /* rootfs_h */
