# Migración de GCC a LLVM/Clang

Esta rama (`llvm`) contiene una migración experimental del vitasdk de GCC a LLVM/Clang como compilador principal.

## Cambios principales

### 1. Reemplazo del compilador
- **Antes**: GCC 15.2.0
- **Ahora**: LLVM/Clang 19.1.7

### 2. Herramientas de compilación cruzada
Las siguientes variables han sido actualizadas para usar LLVM:

- `CC_FOR_TARGET`: `clang` (antes `arm-vita-eabi-gcc`)
- `CXX_FOR_TARGET`: `clang++` (antes `arm-vita-eabi-g++`)
- `AR_FOR_TARGET`: `llvm-ar` (antes `arm-vita-eabi-ar`)
- `RANLIB_FOR_TARGET`: `llvm-ranlib` (antes `arm-vita-eabi-ranlib`)
- `OBJCOPY_FOR_TARGET`: `llvm-objcopy` (antes `arm-vita-eabi-objcopy`)
- `OBJDUMP_FOR_TARGET`: `llvm-objdump` (antes `arm-vita-eabi-objdump`)
- `NM_FOR_TARGET`: `llvm-nm` (antes `arm-vita-eabi-nm`)
- `STRIP_FOR_TARGET`: `llvm-strip` (antes `arm-vita-eabi-strip`)
- `READELF_FOR_TARGET`: `llvm-readelf` (antes `arm-vita-eabi-readelf`)

### 3. Binutils
Se mantiene binutils para las siguientes herramientas:
- `ld` (linker) - Se usa el linker de binutils por compatibilidad
- `as` (assembler) - Se usa el ensamblador de binutils por compatibilidad

Nota: LLD (el linker de LLVM) está disponible pero no se usa por defecto en esta primera versión.

### 4. Componentes LLVM incluidos
- **clang**: Compilador de C/C++
- **lld**: Linker (disponible pero no usado por defecto)
- **compiler-rt**: Runtime del compilador para builtins ARM

### 5. Configuración de LLVM
```cmake
-DLLVM_TARGETS_TO_BUILD=ARM
-DLLVM_DEFAULT_TARGET_TRIPLE=arm-vita-eabi
-DLLVM_ENABLE_PROJECTS=clang;lld;compiler-rt
-DCOMPILER_RT_BUILD_BUILTINS=ON
-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
```

### 6. Dependencias
LLVM requiere menos dependencias de build que GCC:
- ✅ Mantiene: zlib
- ❌ No requiere: GMP, MPFR, MPC, ISL (solo para GCC)

## Estado actual

### ✅ Completado
- [x] Configuración básica de LLVM
- [x] Integración de clang como compilador principal
- [x] Actualización de variables de herramientas de compilación cruzada
- [x] Actualización de dependencias (newlib, pthread-embedded, vita-headers)
- [x] Comentar código de GCC (preservado para referencia)

### 🚧 En pruebas
- [ ] Compilación completa del vitasdk en macOS
- [ ] Verificación de compatibilidad con vita-headers
- [ ] Compilación de samples
- [ ] Pruebas en otras plataformas (Linux, Windows)

### 📋 Por hacer
- [ ] Optimizar flags de compilación para ARM Cortex-A9
- [ ] Evaluar el uso de LLD en lugar de ld de binutils
- [ ] Documentar diferencias de comportamiento con GCC
- [ ] Benchmarks de rendimiento GCC vs LLVM

## Compilación

### macOS (nativo)
```bash
mkdir build
cd build
cmake ..
make -j$(sysctl -n hw.ncpu)
```

### Linux (nativo)
```bash
mkdir build
cd build
cmake ..
make -j$(nproc)
```

## Notas técnicas

### Diferencias de flags con GCC
LLVM/Clang puede requerir flags diferentes o tener comportamientos distintos:
- Los warnings pueden ser diferentes
- La generación de código puede optimizarse de forma distinta
- Algunas extensiones de GCC pueden no estar disponibles

### Compatibilidad con código existente
- El código que usa extensiones específicas de GCC puede necesitar ajustes
- Las pragmas y attributes pueden comportarse de forma diferente
- Se recomienda probar thoroughly antes de usar en producción

## Problemas conocidos

1. **Primera compilación**: LLVM tarda más en compilar que GCC (especialmente en macOS)
2. **Tamaño del build**: LLVM requiere más espacio de disco durante la compilación
3. **Compatibilidad**: Algunos proyectos pueden requerir ajustes para compilar con Clang

## Contribuir

Si encuentras problemas o mejoras, por favor:
1. Documenta el problema/mejora
2. Crea un issue en el repositorio
3. Propón una solución si es posible

## Referencias

- [LLVM Project](https://llvm.org/)
- [Clang Documentation](https://clang.llvm.org/docs/)
- [VitaSDK Documentation](https://vitasdk.org/)
