import 'dart:convert';
import 'dart:io';

import 'package:hospital_api/config/database.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main() async {
  try {
    final db = await connectDatabase();

    final router = Router();

    // Test API
    router.get('/api/test', (Request request) {
      return Response.ok(
        jsonEncode({'message': 'Hospital Appointment API is working!'}),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    });

    // Get all doctors
    router.get('/api/doctors', (Request request) async {
      final doctors = await db.collection('doctors').find().toList();

      final result = doctors.map((doctor) {
        return {
          'id': doctor['_id'].toString(),
          'name': doctor['name'],
          'specialty': doctor['specialty'],
          'hospital': doctor['hospital'],
          'rating': doctor['rating'],
          'reviewCount': doctor['reviewCount'],
          'experience': doctor['experience'],
          'languages': doctor['languages'],
          'available': doctor['available'],
        };
      }).toList();

      return Response.ok(
        jsonEncode(result),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    });

    // Get doctor by ID
    router.get('/api/doctors/<id>', (Request request, String id) async {
      try {
        final doctorId = ObjectId.fromHexString(id);

        final doctor = await db
            .collection('doctors')
            .findOne(where.eq('_id', doctorId));

        if (doctor == null) {
          return Response.notFound(
            jsonEncode({'message': 'Doctor not found'}),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        final result = {
          'id': doctor['_id'].toString(),
          'name': doctor['name'],
          'specialty': doctor['specialty'],
          'hospital': doctor['hospital'],
          'rating': doctor['rating'],
          'reviewCount': doctor['reviewCount'],
          'experience': doctor['experience'],
          'languages': doctor['languages'],
          'available': doctor['available'],
        };

        return Response.ok(
          jsonEncode(result),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      } catch (e) {
        return Response.badRequest(
          body: jsonEncode({'message': 'Invalid doctor ID'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }
    });

    // Get doctor schedule
    router.get('/api/doctors/<id>/schedule', (
      Request request,
      String id,
    ) async {
      final schedules = await db
          .collection('doctor_schedules')
          .find(where.eq('doctorId', id))
          .toList();

      final result = schedules.map((schedule) {
        return {
          'id': schedule['_id'].toString(),
          'doctorId': schedule['doctorId'],
          'doctorName': schedule['doctorName'],
          'date': schedule['date'],
          'day': schedule['day'],
          'availableTimes': schedule['availableTimes'],
        };
      }).toList();

      return Response.ok(
        jsonEncode(result),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    });

    // Create an appointment
    router.post('/api/appointments', (Request request) async {
      try {
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final patientId = data['patientId']?.toString();
        final doctorId = data['doctorId']?.toString();
        final date = data['date']?.toString();
        final time = data['time']?.toString();

        if (patientId == null ||
            patientId.isEmpty ||
            doctorId == null ||
            doctorId.isEmpty ||
            date == null ||
            date.isEmpty ||
            time == null ||
            time.isEmpty) {
          return Response(
            400,
            body: jsonEncode({
              'message': 'patientId, doctorId, date, and time are required.',
            }),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        // Check that the doctor exists.
        final doctor = await db
            .collection('doctors')
            .findOne(where.eq('_id', ObjectId.fromHexString(doctorId)));

        if (doctor == null) {
          return Response(
            404,
            body: jsonEncode({'message': 'Doctor not found.'}),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        final appointment = {
          'patientId': patientId,
          'doctorId': doctorId,
          'doctorName': doctor['name'],
          'hospital': doctor['hospital'],
          'date': date,
          'time': time,
          'reason': data['reason']?.toString() ?? 'General Checkup',
          'status': 'confirmed',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        };

        final result = await db
            .collection('appointments')
            .insertOne(appointment);

        return Response(
          201,
          body: jsonEncode({
            'message': 'Appointment booked successfully.',
            'appointment': {
              ...appointment,
              'id': result.id is ObjectId
                  ? (result.id as ObjectId).oid
                  : result.id.toString(),
            },
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      } on FormatException {
        return Response(
          400,
          body: jsonEncode({'message': 'Invalid JSON or ID format.'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      } catch (e) {
        return Response(
          500,
          body: jsonEncode({'message': 'Failed to book appointment.'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }
    });

    // Reschedule an appointment
    router.patch('/api/appointments/<id>/reschedule', (
      Request request,
      String id,
    ) async {
      try {
        if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(id)) {
        return Response.badRequest(
          body: jsonEncode({'message': 'Invalid appointment ID.'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }

        final appointmentId = ObjectId.fromHexString(id);

        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;

        final date = data['date']?.toString();
        final time = data['time']?.toString();

        if (date == null || date.isEmpty || time == null || time.isEmpty) {
          return Response(
            400,
            body: jsonEncode({'message': 'Date and time are required.'}),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        final appointments = db.collection('appointments');

        final appointment = await appointments.findOne(
          where.eq('_id', appointmentId),
        );

        if (appointment == null) {
          return Response.notFound(
            jsonEncode({'message': 'Appointment not found.'}),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        if (appointment['status'] == 'cancelled') {
          return Response(
            409,
            body: jsonEncode({
              'message': 'Cancelled appointments cannot be rescheduled.',
            }),
            headers: {HttpHeaders.contentTypeHeader: 'application/json'},
          );
        }

        await appointments.updateOne(
          where.eq('_id', appointmentId),
          modify
              .set('date', date)
              .set('time', time)
              .set('status', 'confirmed')
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );

        return Response.ok(
          jsonEncode({
            'message': 'Appointment rescheduled successfully.',
            'appointment': {
              'id': id,
              'patientId': appointment['patientId'],
              'doctorId': appointment['doctorId'],
              'doctorName': appointment['doctorName'],
              'hospital': appointment['hospital'],
              'date': date,
              'time': time,
              'reason': appointment['reason'],
              'status': 'confirmed',
            },
          }),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      } on FormatException {
        return Response.badRequest(
          body: jsonEncode({'message': 'Invalid JSON or appointment ID.'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      } catch (e) {
        return Response(
          500,
          body: jsonEncode({'message': 'Failed to reschedule appointment.'}),
          headers: {HttpHeaders.contentTypeHeader: 'application/json'},
        );
      }
    });
    
    // Cancel an appointment
    router.patch('/api/appointments/<id>/cancel', (
      Request request,
      String id,
    ) async {
      try {
        // Validate appointment ID first
        if (!RegExp(r'^[0-9a-fA-F]{24}$').hasMatch(id)) {
          return Response.badRequest(
            body: jsonEncode({
              'message': 'Invalid appointment ID.',
            }),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
            },
          );
        }

        final appointments = db.collection('appointments');
        final appointmentId = ObjectId.fromHexString(id);

        final appointment = await appointments.findOne(
          where.eq('_id', appointmentId),
        );

        if (appointment == null) {
          return Response.notFound(
            jsonEncode({
              'message': 'Appointment not found.',
            }),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
            },
          );
        }

        if (appointment['status'] == 'cancelled') {
          return Response(
            409,
            body: jsonEncode({
              'message': 'Appointment is already cancelled.',
            }),
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json',
            },
          );
        }

        await appointments.updateOne(
          where.eq('_id', appointmentId),
          modify
              .set('status', 'cancelled')
              .set('updatedAt', DateTime.now().toUtc().toIso8601String()),
        );

        return Response.ok(
          jsonEncode({
            'message': 'Appointment cancelled successfully.',
            'appointment': {
              'id': id,
              'patientId': appointment['patientId'],
              'doctorId': appointment['doctorId'],
              'doctorName': appointment['doctorName'],
              'hospital': appointment['hospital'],
              'date': appointment['date'],
              'time': appointment['time'],
              'reason': appointment['reason'],
              'status': 'cancelled',
            },
          }),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
          },
        );
      } catch (e) {
        print('Cancel appointment error: $e');

        return Response(
          500,
          body: jsonEncode({
            'message': 'Failed to cancel appointment.',
          }),
          headers: {
            HttpHeaders.contentTypeHeader: 'application/json',
          },
        );
      }
    });

    // Get appointments for a patient
    router.get('/api/appointments/<userId>', (
      Request request,
      String userId,
    ) async {
      final appointments = await db
          .collection('appointments')
          .find(where.eq('patientId', userId))
          .toList();

      final result = appointments.map((appointment) {
        return {
          'id': (appointment['_id'] as ObjectId).oid,
          'patientId': appointment['patientId'],
          'doctorId': appointment['doctorId'],
          'doctorName': appointment['doctorName'],
          'hospital': appointment['hospital'],
          'date': appointment['date'],
          'time': appointment['time'],
          'reason': appointment['reason'],
          'status': appointment['status'],
          'createdAt': appointment['createdAt'],
        };
      }).toList();

      return Response.ok(
        jsonEncode(result),
        headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      );
    });

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addHandler(router.call);

    final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);

    print('Hospital API running at http://localhost:${server.port}');
  } catch (e) {
    print('Failed to start API: $e');
  }
}
