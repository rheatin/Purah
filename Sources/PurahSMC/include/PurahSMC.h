#ifndef PURAH_SMC_H
#define PURAH_SMC_H

#ifdef __cplusplus
extern "C" {
#endif

/// Reads an AppleSMC key as a number.
///
/// Handles the scalar types the thermal keys use (`flt`, `sp78`, `fpe2`,
/// `ui8`, `ui16`, `ui32`). Returns 1 on success and 0 when the key is absent
/// or the value cannot be decoded.
int purah_smc_read_number(const char *key, double *value);

#ifdef __cplusplus
}
#endif

#endif /* PURAH_SMC_H */
