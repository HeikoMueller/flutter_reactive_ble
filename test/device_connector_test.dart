import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_reactive_ble/src/device_connector.dart';
import 'package:flutter_reactive_ble/src/discovered_devices_registry.dart';
import 'package:flutter_reactive_ble/src/model/scan_session.dart';
import 'package:flutter_reactive_ble/src/plugin_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('$DeviceConnector', () {
    DeviceConnector _sut;
    _PluginControllerMock _pluginController;
    Stream<ConnectionStateUpdate> _connectionStateUpdateStream;
    Stream<ConnectionStateUpdate> _result;
    _DiscoveredDevicesRegistryMock _registry;
    _DeviceScannerMock _scanner;

    Map<Uuid, List<Uuid>> _servicesToDiscover;
    ConnectionStateUpdate updateForDevice;
    ConnectionStateUpdate updateOtherDevice;

    const _deviceId = '123';
    const _connectionTimeout = Duration(seconds: 1);
    const _delayAfterFailure = Duration(milliseconds: 10);

    setUp(() {
      _pluginController = _PluginControllerMock();
      _registry = _DiscoveredDevicesRegistryMock();
      _scanner = _DeviceScannerMock();
      _servicesToDiscover = {
        Uuid.parse('FEFE'): [Uuid.parse('FEFE')]
      };
      when(_pluginController.connectionUpdateStream)
          .thenAnswer((_) => _connectionStateUpdateStream);

      updateForDevice = const ConnectionStateUpdate(
        deviceId: _deviceId,
        connectionState: DeviceConnectionState.connecting,
        failure: null,
      );

      updateOtherDevice = const ConnectionStateUpdate(
        deviceId: '333',
        connectionState: DeviceConnectionState.connecting,
        failure: null,
      );
    });

    group('Connect to device', () {
      group('Given connection update stream has updates for device', () {
        setUp(() {
          _connectionStateUpdateStream = Stream.fromIterable([
            updateOtherDevice,
            updateForDevice,
          ]);
        });

        group('And invoking connect method succeeds', () {
          setUp(() async {
            when(_pluginController.connectToDevice(any, any, any)).thenAnswer(
              (_) => Stream.fromIterable([1]),
            );

            _sut = DeviceConnector(
              pluginController: _pluginController,
              discoveredDevicesRegistry: _registry,
              scanForDevices: _scanner.scanForDevices,
              getCurrentScan: _scanner.getCurrentScan,
              delayAfterScanFailure: _delayAfterFailure,
            );
            _result = _sut.connect(
              id: _deviceId,
              servicesWithCharacteristicsToDiscover: _servicesToDiscover,
              connectionTimeout: _connectionTimeout,
            );
          });

          test('It emits connection updates for that device', () {
            expect(_result,
                emitsInOrder(<ConnectionStateUpdate>[updateForDevice]));
          });

          test('It invokes method connect device', () async {
            await _result.first;
            verify(_pluginController.connectToDevice(
              _deviceId,
              _servicesToDiscover,
              _connectionTimeout,
            )).called(1);
          });

          test('It invokes method disconnect when stream is cancelled',
              () async {
            final subscription = _result.listen((event) {});

            await subscription.cancel();

            verify(_pluginController.disconnectDevice(_deviceId)).called(1);
          });
        });
      });
    });

    group('Connect to advertising device', () {
      const deviceId = '123';
      final uuidDeviceToScan = Uuid.parse('FEFF');
      final uuidCurrentScan = Uuid.parse('FEFE');
      const discoveredDevice = DiscoveredDevice(
        id: 'deviceId',
        manufacturerData: null,
        name: 'test',
        rssi: -39,
        serviceData: {},
      );

      setUp(() {
        _connectionStateUpdateStream = Stream.fromIterable([
          updateForDevice,
        ]);
      });
      group('Given a scan is running for another device', () {
        setUp(() {
          when(_scanner.getCurrentScan()).thenReturn(
            ScanSession(
              future: Future.value(),
              withServices: [uuidCurrentScan],
            ),
          );

          _sut = DeviceConnector(
            pluginController: _pluginController,
            discoveredDevicesRegistry: _registry,
            scanForDevices: _scanner.scanForDevices,
            getCurrentScan: _scanner.getCurrentScan,
            delayAfterScanFailure: _delayAfterFailure,
          );

          _result = _sut.connectToAdvertisingDevice(
            id: deviceId,
            withServices: [uuidDeviceToScan],
            prescanDuration: const Duration(milliseconds: 10),
          );
        });

        test('It emits connection update with failure', () {
          const expectedUpdate = ConnectionStateUpdate(
            deviceId: deviceId,
            connectionState: DeviceConnectionState.disconnected,
            failure: GenericFailure(
              code: ConnectionError.failedToConnect,
              message: "A scan for a different service is running",
            ),
          );

          expect(
              _result, emitsInOrder(<ConnectionStateUpdate>[expectedUpdate]));
        });
      });

      group('Given a scan is running for the same device device', () {
        final uuidDeviceToScan = Uuid.parse('FEFF');

        setUp(() {
          when(_scanner.getCurrentScan()).thenReturn(
            ScanSession(
              future: Future.value(),
              withServices: [uuidDeviceToScan],
            ),
          );
        });

        group('And device is discovered', () {
          setUp(() {
            when(_registry.deviceIsDiscoveredRecently(
                    deviceId: deviceId,
                    cacheValidity: anyNamed('cacheValidity')))
                .thenReturn(true);
            when(_pluginController.connectToDevice(any, any, any))
                .thenAnswer((_) => Stream.fromIterable([1]));
            _sut = DeviceConnector(
              pluginController: _pluginController,
              discoveredDevicesRegistry: _registry,
              scanForDevices: _scanner.scanForDevices,
              getCurrentScan: _scanner.getCurrentScan,
              delayAfterScanFailure: _delayAfterFailure,
            );
            _result = _sut.connectToAdvertisingDevice(
              id: deviceId,
              withServices: [uuidDeviceToScan],
              prescanDuration: const Duration(milliseconds: 10),
            );
          });

          test('It connects to device after scan has finished', () {
            expect(_result,
                emitsInOrder(<ConnectionStateUpdate>[updateForDevice]));
          });
        });

        group('And device is not found after scanning', () {
          setUp(() {
            when(_registry.deviceIsDiscoveredRecently(
                    deviceId: deviceId,
                    cacheValidity: anyNamed('cacheValidity')))
                .thenReturn(false);

            _sut = DeviceConnector(
              pluginController: _pluginController,
              discoveredDevicesRegistry: _registry,
              scanForDevices: _scanner.scanForDevices,
              getCurrentScan: _scanner.getCurrentScan,
              delayAfterScanFailure: _delayAfterFailure,
            );
            _result = _sut.connectToAdvertisingDevice(
              id: deviceId,
              withServices: [uuidDeviceToScan],
              prescanDuration: const Duration(milliseconds: 10),
            );
          });
          test('It emits failure', () {
            const expectedUpdate = ConnectionStateUpdate(
              deviceId: deviceId,
              connectionState: DeviceConnectionState.disconnected,
              failure: GenericFailure(
                code: ConnectionError.failedToConnect,
                message: "Device is not advertising",
              ),
            );

            expect(
                _result, emitsInOrder(<ConnectionStateUpdate>[expectedUpdate]));
          });
        });
      });

      group('Given no scan is running', () {
        setUp(() {
          final session = ScanSession(
              future: Future.value(), withServices: [uuidDeviceToScan]);

          final responses = [null, session, session];

          when(_scanner.getCurrentScan())
              .thenAnswer((_) => responses.removeAt(0));
        });

        group('And device is discovered in a previous scan', () {
          setUp(() {
            when(_registry.deviceIsDiscoveredRecently(
                    deviceId: deviceId,
                    cacheValidity: anyNamed('cacheValidity')))
                .thenReturn(true);
            when(_pluginController.connectToDevice(any, any, any))
                .thenAnswer((_) => Stream.fromIterable([1]));
            _sut = DeviceConnector(
              pluginController: _pluginController,
              discoveredDevicesRegistry: _registry,
              scanForDevices: _scanner.scanForDevices,
              getCurrentScan: _scanner.getCurrentScan,
              delayAfterScanFailure: _delayAfterFailure,
            );
            _result = _sut.connectToAdvertisingDevice(
              id: deviceId,
              withServices: [uuidDeviceToScan],
              prescanDuration: const Duration(milliseconds: 10),
            );
          });

          test('It emits device update', () {
            expect(_result,
                emitsInOrder(<ConnectionStateUpdate>[updateForDevice]));
          });

          test('It does not scan for devices', () async {
            await _result.first;

            verifyNever(_scanner.scanForDevices(
              withServices: anyNamed('withServices'),
              scanMode: anyNamed('scanMode'),
            ));
          });
        });

        group('And device is not discovered in a previous scan', () {
          setUp(() {
            when(_scanner.scanForDevices(
              withServices: anyNamed('withServices'),
              scanMode: anyNamed('scanMode'),
            )).thenAnswer((_) => Stream.fromIterable([discoveredDevice]));
          });

          group('And device is not found after scanning', () {
            setUp(() {
              when(_registry.deviceIsDiscoveredRecently(
                      deviceId: deviceId,
                      cacheValidity: anyNamed('cacheValidity')))
                  .thenReturn(false);

              _sut = DeviceConnector(
                pluginController: _pluginController,
                discoveredDevicesRegistry: _registry,
                scanForDevices: _scanner.scanForDevices,
                getCurrentScan: _scanner.getCurrentScan,
                delayAfterScanFailure: _delayAfterFailure,
              );
              _result = _sut.connectToAdvertisingDevice(
                id: deviceId,
                withServices: [uuidDeviceToScan],
                prescanDuration: const Duration(milliseconds: 10),
              );
            });
            test('It scans for devices', () async {
              await _result.first;
              verify(
                _scanner.scanForDevices(
                  withServices: anyNamed('withServices'),
                  scanMode: anyNamed('scanMode'),
                ),
              ).called(1);
            });

            test('It emits failure', () {
              const expectedUpdate = ConnectionStateUpdate(
                deviceId: deviceId,
                connectionState: DeviceConnectionState.disconnected,
                failure: GenericFailure(
                  code: ConnectionError.failedToConnect,
                  message: "Device is not advertising",
                ),
              );

              expect(_result,
                  emitsInOrder(<ConnectionStateUpdate>[expectedUpdate]));
            });
          });
          group('And device found after scanning', () {
            setUp(() {
              final responses = [false, true, true, true];
              when(_registry.deviceIsDiscoveredRecently(
                      deviceId: deviceId,
                      cacheValidity: anyNamed('cacheValidity')))
                  .thenAnswer((_) => responses.removeAt(0));

              when(_pluginController.connectToDevice(any, any, any))
                  .thenAnswer((_) => Stream.fromIterable([1]));

              _sut = DeviceConnector(
                pluginController: _pluginController,
                discoveredDevicesRegistry: _registry,
                scanForDevices: _scanner.scanForDevices,
                getCurrentScan: _scanner.getCurrentScan,
                delayAfterScanFailure: _delayAfterFailure,
              );
              _result = _sut.connectToAdvertisingDevice(
                id: deviceId,
                withServices: [uuidDeviceToScan],
                prescanDuration: const Duration(milliseconds: 10),
              );
            });
            test('It scans for devices', () async {
              await _result.first;
              verify(
                _scanner.scanForDevices(
                  withServices: anyNamed('withServices'),
                  scanMode: anyNamed('scanMode'),
                ),
              ).called(1);
            });

            test('It emits device update', () {
              expect(_result,
                  emitsInOrder(<ConnectionStateUpdate>[updateForDevice]));
            });
          });
        });
      });
    });
  });
}

class _PluginControllerMock extends Mock implements PluginController {}

class _DiscoveredDevicesRegistryMock extends Mock
    implements DiscoveredDevicesRegistry {}

class _DeviceScannerMock extends Mock {
  Stream<DiscoveredDevice> scanForDevices(
      {List<Uuid> withServices, ScanMode scanMode});
  ScanSession getCurrentScan();
}
