#include "libjb.h"
#include "../kernel.h"
#include <mach/mach.h>
#include "patchfinder64.h"
#include <stdio.h>
#include <stdlib.h>
#include <Foundation/Foundation.h>
#include <mach-o/dyld.h>
#include <spawn.h>
#include <sys/stat.h>

task_t taskfp0;

kern_return_t mach_vm_read_overwrite(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outsize);
kern_return_t mach_vm_write(vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt);
kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);


size_t
kread(uint64_t where, void *p, size_t size)
{
    
    int rv;
    size_t offset = 0;
    while (offset < size) {
        mach_vm_size_t sz, chunk = 2048;
        if (chunk > size - offset) {
            chunk = size - offset;
        }
        rv = mach_vm_read_overwrite(taskfp0, where + offset, chunk, (mach_vm_address_t)p + offset, &sz);
        if (rv || sz == 0) {
            fprintf(stderr, "[e] error reading kernel @%p\n", (void *)(offset + where));
            break;
        }
        offset += sz;
    }
    return offset;
}

/*size_t kwrite(uint64_t where, const void *p, size_t size) {
   // printf("taskfp0: %d", taskfp0);
        int rv;
        size_t offset = 0;
        while (offset < size) {
                size_t chunk = 2048;
                if (chunk > size - offset) {
                        chunk = size - offset;
                    }
                rv = mach_vm_write(taskfp0, where + offset, (mach_vm_offset_t)p + offset, chunk);
                if (rv) {
                        fprintf(stderr, "[e] error writing kernel @%p\n", (void *)(offset + where));
                        break;
                    }
                offset += chunk;
            }
        return offset;
    }*/

void kwrite32(uint64_t where, uint32_t what) {
    uint32_t _what = what;
    kwrite(where, &_what, sizeof(uint32_t));
}


void kwrite64(uint64_t where, uint64_t what) {
    uint64_t _what = what;
    kwrite(where, &_what, sizeof(uint64_t));
}

static uint64_t kalloc(vm_size_t size){
  //  printf("taskfp0: %d", taskfp0);
        mach_vm_address_t address = 0;
        mach_vm_allocate(taskfp0, (mach_vm_address_t *)&address, size, VM_FLAGS_ANYWHERE);
        return address;
    }

int cp(const char *to, const char *from)
{
    int fd_to, fd_from;
    char buf[4096];
    ssize_t nread;
    int saved_errno;
    
    fd_from = open(from, O_RDONLY);
    if (fd_from < 0)
        return -1;
    
    fd_to = open(to, O_WRONLY | O_CREAT | O_EXCL, 0666);
    if (fd_to < 0)
        goto out_error;
    
    while (nread = read(fd_from, buf, sizeof buf), nread > 0)
    {
        char *out_ptr = buf;
        ssize_t nwritten;
        
        do {
            nwritten = write(fd_to, out_ptr, nread);
            
            if (nwritten >= 0)
            {
                nread -= nwritten;
                out_ptr += nwritten;
            }
            else if (errno != EINTR)
            {
                goto out_error;
            }
        } while (nread > 0);
    }
    
    if (nread == 0)
    {
        if (close(fd_to) < 0)
        {
            fd_to = -1;
            goto out_error;
        }
        close(fd_from);
        
        /* Success! */
        return 0;
    }
    
out_error:
    saved_errno = errno;
    
    close(fd_from);
    if (fd_to >= 0)
        close(fd_to);
    
    errno = saved_errno;
    return -1;
}

int patch_amfi(task_t tfpzero, uint64_t kslide, bool isv0rtex, bool hastweaks) {
    taskfp0 = tfpzero;
    //printf("taskfp0: %d", taskfp0);
    init_patchfinder(taskfp0, 0xfffffff007004000 + kslide, NULL); //start patchfinder
    uint64_t trust_chain = find_trustcache(); //find trust cache
    uint64_t amficache = find_amficache(); //find amficache
    printf("trust_chain = 0x%llx\n", trust_chain);
    printf("amficache = 0x%llx\n", amficache);
    struct trust_mem mem;
    mem.next = rk64(taskfp0, trust_chain);
    *(uint64_t *)&mem.uuid[0] = 0xabadbabeabadbabe;
    *(uint64_t *)&mem.uuid[8] = 0xabadbabeabadbabe;
    
    //USAGE:
    //call grab_hashes to trust a binary
    //EXAMPLE: grab_hashes("/usr/bin", kread, amficache, mem.next)
    
    //first amfi patch
    
    if (isv0rtex) {
    printf("v0rtex rv = %d, numhash = %d\n", grab_hashes("/v0rtex", kread, amficache, mem.next), numhash);
    printf("v0rtex rv = %d, numhash = %d\n", grab_hashes("/bin", kread, amficache, mem.next), numhash);
    printf("usr rv = %d, numhash = %d\n", grab_hashes("/usr", kread, amficache, mem.next), numhash);
    printf("sbin rv = %d, numhash = %d\n", grab_hashes("/sbin", kread, amficache, mem.next), numhash);
        
    if (hastweaks) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory,@"tweak.deb"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSLog(@"\npath = %@ \n", filePath);
            NSString *cmd = [NSString stringWithFormat:@"dpkg --ignore-depends mobilesubstrate,preferenceloader -i %@", filePath];//TODO: properly install mobilesubstrate so I don't have to ignore the dependency
          system([cmd UTF8String]); //install
          sleep(2);
          [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil]; //clean up
      }
   }
}
    //second amfi patch
    else {
    /* printf("usrbin rv = %d, numhash = %d\n", grab_hashes("/usr/bin", kread, amficache, mem.next), numhash);
   printf("localbin rv = %d, numhash = %d\n", grab_hashes("/usr/local/bin", kread, amficache, mem.next), numhash);
    printf("bin rv = %d, numhash = %d\n", grab_hashes("/bin", kread, amficache, mem.next), numhash);
    printf("sbin rv = %d, numhash = %d\n", grab_hashes("/sbin", kread, amficache, mem.next), numhash);
        printf("Apps rv = %d, numhash = %d\n", grab_hashes("/Applications", kread, amficache, mem.next), numhash);
    printf("usrlib rv = %d, numhash = %d\n", grab_hashes("/usr/lib", kread, amficache, mem.next), numhash);
        printf("usrlibexec rv = %d, numhash = %d\n", grab_hashes("/usr/libexec", kread, amficache, mem.next), numhash);
    printf("substratelib rv = %d, numhash = %d\n", grab_hashes("/Library/Frameworks/CydiaSubstrate.framework", kread, amficache, mem.next), numhash);
    printf("dylibs rv = %d, numhash = %d\n", grab_hashes("/Library/MobileSubstrate", kread, amficache, mem.next), numhash);*/
        
        printf("usr rv = %d, numhash = %d\n", grab_hashes("/usr", kread, amficache, mem.next), numhash);
        printf("bin rv = %d, numhash = %d\n", grab_hashes("/bin", kread, amficache, mem.next), numhash);
        printf("sbin rv = %d, numhash = %d\n", grab_hashes("/sbin", kread, amficache, mem.next), numhash);
        printf("Apps rv = %d, numhash = %d\n", grab_hashes("/Applications", kread, amficache, mem.next), numhash);
        printf("Library rv = %d, numhash = %d\n", grab_hashes("/Library", kread, amficache, mem.next), numhash);
        
       // printf("dylibs rv = %d, numhash = %d\n", grab_hashes("/Library/MobileSubstrate", kread, amficache, mem.next), numhash);
        
    
    }
    
    size_t length = (sizeof(mem) + numhash * 20 + 0xFFFF) & ~0xFFFF;
    uint64_t kernel_trust = kalloc(length);
    printf("alloced: 0x%zx => 0x%llx\n", length, kernel_trust);
    
    mem.count = numhash;
    kwrite(kernel_trust, &mem, sizeof(mem));
    kwrite(kernel_trust + sizeof(mem), allhash, numhash * 20);
    kwrite64(trust_chain, kernel_trust);
    
    if (!isv0rtex) {
    free(allhash);
    free(allkern);
    free(amfitab);
    }
    //this is the old code
    //char *tt = "echo 'dlopen(\"/Library/MobileSubstrate/MobileSubstrate.dylib\", RTLD_LAZY)'| cycript -p SpringBoard";
    //printf("\n THIS CYC: %s \n", tt);
    //system(tt);
    //system("launchctl load /Library/LaunchDaemons/*");
    
    return 0;
}