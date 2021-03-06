import 'package:flutter_reactive_ble/src/converter/args_to_protubuf_converter.dart';
import 'package:flutter_reactive_ble/src/generated/bledata.pbserver.dart' as pb;
import 'package:flutter_reactive_ble/src/model/uuid.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('$ArgsToProtobufConverter', () {
    const _sut = ArgsToProtobufConverter();

    group('Connect to device args', () {
      const deviceId = '123';
      Map<Uuid, List<Uuid>> servicesToDiscover;
      Duration timeout;
      pb.ConnectToDeviceRequest result;

      group('And servicesToDiscover is not null', () {
        setUp(() {
          servicesToDiscover = {
            Uuid.parse('FEFE'): [Uuid.parse('FEFE')]
          };
        });

        group('And timeout is not null', () {
          setUp(() {
            timeout = const Duration(seconds: 2);
            result = _sut.createConnectToDeviceArgs(
                deviceId, servicesToDiscover, timeout);
          });

          test('It converts deviceId', () {
            expect(result.deviceId, deviceId);
          });

          test('It converts timeout', () {
            expect(result.timeoutInMs, 2000);
          });

          test('It converts servicesToDiscover', () {
            final uuid = pb.Uuid()..data = [254, 254];
            final expectedServiceWithChar = pb.ServiceWithCharacteristics()
              ..serviceId = uuid
              ..characteristics.add(uuid);
            expect(result.servicesWithCharacteristicsToDiscover.items,
                [expectedServiceWithChar]);
          });
        });

        group('And timeout is null', () {
          setUp(() {
            timeout = null;
            result = _sut.createConnectToDeviceArgs(
                deviceId, servicesToDiscover, timeout);
          });
          test('It sets timeout to default value', () {
            expect(result.timeoutInMs, 0);
          });
        });
      });

      group('And servicesToDiscover is null', () {
        setUp(() {
          servicesToDiscover = null;
          result = _sut.createConnectToDeviceArgs(
              deviceId, servicesToDiscover, timeout);
        });

        test('It converts servicesToDiscover to default', () {
          expect(result.servicesWithCharacteristicsToDiscover,
              pb.ServicesWithCharacteristics());
        });
      });
    });

    group('Disconnect device', () {
      const deviceId = '123';
      pb.DisconnectFromDeviceRequest result;

      setUp(() {
        result = _sut.createDisconnectDeviceArgs(deviceId);
      });

      test('It sets correct device id', () {
        expect(result.deviceId, deviceId);
      });
    });
  });
}
