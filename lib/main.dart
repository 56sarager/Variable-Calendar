import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth.dart';
import 'not.dart';
import 'secrets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: FirebaseOptions(
      apiKey: firebaseapiKey,
      authDomain: firebaseauthDomain,
      projectId: firebaseprojectId,
      storageBucket: firebasestorageBucket,
      messagingSenderId: firebasemessagingSenderId,
      appId: firebaseappId,
      measurementId: firebasemeasurementId,
    ),
  );
  runApp(RestartWidget(child: MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return CircularProgressIndicator();
          } else if (snapshot.hasData) {
            return CalendarScreen();
          } else {
            return LoginScreen();
          }
        },
      ),
    );
  }
}

class Event {
  int? id;
  String title;
  DateTime dateTime; // Store both date and time as DateTime
  String? note;
  Color color;
  String? userId;

  Event({
    this.id,
    required this.title,
    required this.dateTime, // Change: Store date and time together
    this.note,
    required this.color,
    required this.userId,
  });

  // Convert the Event object to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'event_time': dateTime.toIso8601String(), // Use the combined DateTime
      'color': color.value.toString(),
      'user_id': userId,
    };
  }

  // Convert JSON to Event object
  static Event fromJson(Map<String, dynamic> json) {
    final DateTime dateTime = DateTime.parse(json['event_time']);
    return Event(
      id: json['id'],
      title: json['title'],
      dateTime: dateTime, // Parse the full DateTime
      color: Color(int.parse(json['color'])),
      userId: json['user_id'],
    );
  }
}

class CalendarScreen extends StatefulWidget {
  @override
  _CalendarScreenState createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.week;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  Map<DateTime, List<Event>> tasks = {};
  String? userId;

  @override
  void initState() {
    super.initState();
    userId = FirebaseAuth.instance.currentUser?.uid; // Get the authenticated user's ID
    _fetchTasksFromDatabase(); // Fetch events from SQL on load
  }

  Future<void> _signOut() async {
  await FirebaseAuth.instance.signOut();
  RestartWidget.restartApp(context); // Restart the entire app
}
 void _navigateToNotifications() {
    // Logic for navigating to the notifications screen
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => NotificationScreen()));
  }

  Future<void> _fetchTasksFromDatabase() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:3000/events/$userId'));

      if (response.statusCode == 200) {
        final List<dynamic> eventList = jsonDecode(response.body);

        setState(() {
          tasks.clear(); // Clear existing tasks

          for (var eventJson in eventList) {
            final event = Event.fromJson(eventJson);
            final DateTime eventDay = DateTime(
              event.dateTime.year,
              event.dateTime.month,
              event.dateTime.day,
            );

            // Group events by the day they occur on
            if (!tasks.containsKey(eventDay)) {
              tasks[eventDay] = [];
            }
            tasks[eventDay]?.add(event);
          }

          // Ensure the selected day's tasks are rebuilt
          _getTasksForDay(_selectedDay);
        });
      } else {
        throw Exception('Failed to load tasks');
      }
    } catch (e) {
      print('Error fetching events: $e');
    }
  }

  List<Event> _getTasksForDay(DateTime day) {
    // Return tasks for the day or an empty list if there are no tasks
    return tasks[DateTime(day.year, day.month, day.day)] ?? [];
  }

  Future<void> _addTask(Event task) async {
    final response = await http.post(
      Uri.parse('http://localhost:3000/events'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(task.toJson()),
    );
    if (response.statusCode == 200) {
      final newEvent = Event.fromJson(jsonDecode(response.body));

      final DateTime eventDay = DateTime(
        newEvent.dateTime.year,
        newEvent.dateTime.month,
        newEvent.dateTime.day,
      );

      setState(() {
        tasks[eventDay] = (tasks[eventDay] ?? [])..add(newEvent);
        tasks[eventDay]?.sort((a, b) => _compareTime(a.dateTime, b.dateTime));
      });
    }
  }

  Future<void> _editTask(int index, Event newTask) async {
    final response = await http.put(
      Uri.parse('http://localhost:3000/events/${newTask.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(newTask.toJson()),
    );
    if (response.statusCode == 200) {
      final DateTime eventDay = DateTime(
        newTask.dateTime.year,
        newTask.dateTime.month,
        newTask.dateTime.day,
      );

      setState(() {
        tasks[eventDay]?[index] = newTask;
        tasks[eventDay]?.sort((a, b) => _compareTime(a.dateTime, b.dateTime));
      });
    }
  }

  Future<void> _deleteTask(int index) async {
    final event = tasks[_selectedDay]![index];
    final response = await http.delete(Uri.parse('http://localhost:3000/events/${event.id}'));
    if (response.statusCode == 200) {
      setState(() {
        tasks[_selectedDay]?.removeAt(index);
        if (tasks[_selectedDay]?.isEmpty ?? false) {
          tasks.remove(_selectedDay);
        }
      });
    }
  }

  int _compareTime(DateTime time1, DateTime time2) {
    return time1.compareTo(time2); // Compare full DateTime values
  }

  void _showTaskDialog({Event? event, int? index}) {
    final taskController = TextEditingController(text: event?.title ?? '');
    final noteController = TextEditingController(text: event?.note ?? '');
    TimeOfDay selectedTime = event != null ? TimeOfDay.fromDateTime(event.dateTime) : TimeOfDay.now();
    Color selectedColor = event?.color ?? Colors.blue;
    DateTime selectedDate = event != null ? event.dateTime : _selectedDay;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          title: Text(event == null ? 'Create Event' : 'Edit Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  cursorColor: Colors.lightBlue[900],
                  controller: taskController,
                  decoration: InputDecoration(
                    hintText: 'Enter event title',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Date Picker Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Date: ${DateFormat.yMMMd().format(selectedDate)}'),
                    TextButton(
                      child: Text('Change'),
                      style: TextButton.styleFrom(foregroundColor: Colors.lightBlue[900]),
                      onPressed: () async {
                        DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          builder: (BuildContext context, Widget? child) {
                            return Theme(
                              data: ThemeData.light().copyWith(
                                colorScheme: ColorScheme.light(
                                  primary: Colors.white,
                                  onPrimary: Colors.blue,
                                  onSurface: Colors.blue,
                                ),
                                dialogBackgroundColor: Colors.white,
                                textButtonTheme: TextButtonThemeData(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                  ),
                                ),
                              ),
                              child: child!,
                            );
                          },
                        );
                        if (picked != null && picked != selectedDate) {
                          setState(() {
                            selectedDate = picked; // Update date immediately
                          });
                        }
                      },
                    ),
                  ],
                ),
                // Time Picker Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DropdownButton<int>(
                      value: selectedTime.hour,
                      items: List.generate(24, (index) {
                        return DropdownMenuItem(
                          value: index,
                          child: Text(index.toString().padLeft(2, '0')),
                        );
                      }),
                      onChanged: (value) {
                        setState(() {
                          selectedTime = TimeOfDay(hour: value!, minute: selectedTime.minute);
                        });
                      },
                    ),
                    Text(":"),
                    DropdownButton<int>(
                      value: selectedTime.minute,
                      items: List.generate(60, (index) {
                        return DropdownMenuItem(
                          value: index,
                          child: Text(index.toString().padLeft(2, '0')),
                        );
                      }),
                      onChanged: (value) {
                        setState(() {
                          selectedTime = TimeOfDay(hour: selectedTime.hour, minute: value!);
                        });
                      },
                    ),
                  ],
                ),
                // Notes Section
                TextField(
                  controller: noteController,
                  cursorColor: Colors.lightBlue[900],
                  decoration: InputDecoration(
                    hintText: 'Enter note',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                  ),
                ),
                // Color Picker Section
                MaterialPicker(
                  pickerColor: selectedColor,
                  onColorChanged: (Color color) {
                    setState(() {
                      selectedColor = color;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.lightBlue[900]),
              child: Text('Save'),
              onPressed: () {
                // Automatically save the event with the new date/time and refresh the page
                final DateTime newDateTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );
                final newEvent = Event(
                  id: event?.id,
                  title: taskController.text,
                  dateTime: newDateTime,
                  color: selectedColor,
                  note: noteController.text,
                  userId: userId,
                );
                if (event == null) {
                  _addTask(newEvent);
                } else {
                  _editTask(index!, newEvent);
                }
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.lightBlue[900]),
              child: Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Punctual"),
        backgroundColor: Colors.lightBlue[100],
      ),
      drawer: Drawer(
        child: ListView(
          children: <Widget>[
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.lightBlue[100],
              ),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.calendar_today),
              title: Text('Calendar'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.notifications),
              title: Text('Notifications'),
              onTap: () {
                _navigateToNotifications();
              },
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Log Out'),
              onTap: () {
                _signOut();
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          TableCalendar(
            focusedDay: _focusedDay,
            firstDay: DateTime(2000),
            lastDay: DateTime(2100),
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.lightBlue[900], // Change color for today's date
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.lightBlue[100], // Change color for selected day
                shape: BoxShape.circle,
              ),
            ),
            eventLoader: (day) {
              return _getTasksForDay(day);
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isNotEmpty) {
                  return Positioned(
                    bottom: 4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: events.map((event) {
                        return Container(
                          margin: EdgeInsets.symmetric(horizontal: 1.5),
                          width: 6.0,
                          height: 6.0,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black, // Color of the event dot
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }
                return null;
              },
            ),
          ),
          ..._getTasksForDay(_selectedDay).asMap().entries.map(
                (entry) => ListTile(
                  tileColor: entry.value.color,
                  title: Text(entry.value.title),
                  subtitle: Text(DateFormat.jm().format(entry.value.dateTime)),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _deleteTask(entry.key),
                  ),
                  onTap: () => _showTaskDialog(event: entry.value, index: entry.key),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.lightBlue[100], // Change create event button color
        onPressed: () => _showTaskDialog(),
        child: Icon(Icons.add),
      ),
    );
  }
}






