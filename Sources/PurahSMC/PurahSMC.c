#include "PurahSMC.h"

#include <IOKit/IOKitLib.h>
#include <string.h>
#include <pthread.h>

typedef struct {
    unsigned char major, minor, build, reserved;
    unsigned short release;
} SMCVersion;

typedef struct {
    unsigned short version, length;
    unsigned int cpuPLimit, gpuPLimit, memPLimit;
} SMCPlatLimitData;

typedef struct {
    unsigned int dataSize, dataType;
    unsigned char dataAttributes;
} SMCKeyInfoData;

typedef struct {
    unsigned int key;
    SMCVersion vers;
    SMCPlatLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    unsigned char result, status, data8;
    unsigned int data32;
    unsigned char bytes[32];
} SMCKeyData_t;

static pthread_mutex_t purah_smc_mutex = PTHREAD_MUTEX_INITIALIZER;
static io_connect_t purah_smc_connection = 0;

static io_connect_t purah_smc_open(void) {
    pthread_mutex_lock(&purah_smc_mutex);
    if (purah_smc_connection != 0) {
        io_connect_t conn = purah_smc_connection;
        pthread_mutex_unlock(&purah_smc_mutex);
        return conn;
    }
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("AppleSMC")
    );
    if (service == 0) {
        pthread_mutex_unlock(&purah_smc_mutex);
        return 0;
    }
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) {
        pthread_mutex_unlock(&purah_smc_mutex);
        return 0;
    }
    purah_smc_connection = connection;
    pthread_mutex_unlock(&purah_smc_mutex);
    return connection;
}

static unsigned int purah_four_cc(const char *key) {
    unsigned int value = 0;
    for (int index = 0; index < 4; index++) {
        value = (value << 8) | (unsigned char)key[index];
    }
    return value;
}

int purah_smc_read_number(const char *key, double *value) {
    if (key == NULL || value == NULL) {
        return 0;
    }
    if (strnlen(key, 5) != 4) {
        return 0;
    }
    io_connect_t connection = purah_smc_open();
    if (connection == 0) {
        return 0;
    }

    SMCKeyData_t input;
    SMCKeyData_t output;
    memset(&input, 0, sizeof input);
    memset(&output, 0, sizeof output);
    input.key = purah_four_cc(key);
    input.data8 = 9; /* kSMCGetKeyInfo */
    size_t output_size = sizeof output;
    if (IOConnectCallStructMethod(
            connection,
            2,
            &input,
            sizeof input,
            &output,
            &output_size
        ) != KERN_SUCCESS) {
        return 0;
    }
    if (output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) {
        return 0;
    }

    SMCKeyData_t read_input;
    SMCKeyData_t read_output;
    memset(&read_input, 0, sizeof read_input);
    memset(&read_output, 0, sizeof read_output);
    read_input.key = input.key;
    read_input.keyInfo = output.keyInfo;
    read_input.data8 = 5; /* kSMCReadKey */
    output_size = sizeof read_output;
    if (IOConnectCallStructMethod(
            connection,
            2,
            &read_input,
            sizeof read_input,
            &read_output,
            &output_size
        ) != KERN_SUCCESS) {
        return 0;
    }
    if (read_output.result != 0) {
        return 0;
    }

    unsigned char *bytes = read_output.bytes;
    unsigned int type = output.keyInfo.dataType;
    switch (type) {
    case 0x666c7420: { /* flt */
        float decoded = 0;
        memcpy(&decoded, bytes, sizeof decoded);
        *value = decoded;
        return 1;
    }
    case 0x73703738: { /* sp78 */
        short decoded = (short)(((unsigned short)bytes[0] << 8) | bytes[1]);
        *value = decoded / 256.0;
        return 1;
    }
    case 0x66706532: { /* fpe2 */
        unsigned short decoded = ((unsigned short)bytes[0] << 8) | bytes[1];
        *value = decoded / 4.0;
        return 1;
    }
    case 0x75693820: /* ui8 */
        *value = bytes[0];
        return 1;
    case 0x75693136: /* ui16 */
        *value = ((unsigned short)bytes[0] << 8) | bytes[1];
        return 1;
    case 0x75693332: { /* ui32 */
        unsigned int decoded = ((unsigned int)bytes[0] << 24)
            | ((unsigned int)bytes[1] << 16)
            | ((unsigned int)bytes[2] << 8)
            | bytes[3];
        *value = decoded;
        return 1;
    }
    default:
        return 0;
    }
}
