# wuarikes_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firma del release (Android)

El release se firma con `android/key.properties` (ignorado en git). Sin ese archivo el
AAB sale **sin firmar** y Play Store lo rechaza; nunca se firma con la llave de debug.

1. Crear la llave (una sola vez; guárdala junto con sus contraseñas en un gestor de
   contraseñas: si se pierde, la app no se puede volver a actualizar):

   ```
   keytool -genkey -v -keystore %USERPROFILE%\wuarikes-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Crear `android/key.properties`:

   ```
   storePassword=<contraseña>
   keyPassword=<contraseña>
   keyAlias=upload
   storeFile=C:\Users\<usuario>\wuarikes-upload.jks
   ```

3. `flutter build appbundle --release`

4. Registrar en Google Cloud (cliente OAuth de Android) la huella SHA-1 de esta llave
   **y** la de "App signing" que muestra Play Console, o Google Sign-In fallará en producción:
   `keytool -list -v -keystore %USERPROFILE%\wuarikes-upload.jks -alias upload`
