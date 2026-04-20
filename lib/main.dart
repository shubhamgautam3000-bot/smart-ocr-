import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('ocr_history');
  runApp(const SmartOCRApp());
}

class SmartOCRApp extends StatelessWidget {
  const SmartOCRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OCRHomePage(),
    );
  }
}

class OCRHomePage extends StatefulWidget {
  const OCRHomePage({super.key});

  @override
  State<OCRHomePage> createState() => _OCRHomePageState();
}

class _OCRHomePageState extends State<OCRHomePage> {

  File? _image;
  bool _isScanning = false;
  final Map<String, dynamic> _json = {};

  final List<String> displayOrder = [
    'Document Type',
    'Name',
    'Father Name',
    'Mother Name',
    'Gender',
    'Date of Birth',
    'Blood Group',
    'Address',
    'PAN Number',
    'Aadhaar Number',
    'Driving License Number',
    'Voter ID Number',
    'Issuing Authority',
    'Additional Details',
  ];

  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _recognizer =
  TextRecognizer(script: TextRecognitionScript.latin);

  Future<void> _pick(ImageSource source) async {

    if (Platform.isAndroid && source == ImageSource.camera) {
      if (!(await Permission.camera.request()).isGranted) return;
    }

    final file = await _picker.pickImage(source: source);

    if (file == null) return;

    setState(() {
      _image = File(file.path);
      _isScanning = true;
      _json.clear();
    });

    final inputImage = InputImage.fromFile(_image!);

    final result = await _recognizer.processImage(inputImage);
    _parseBlocks(result);

    setState(() => _isScanning = false);
  }

  // ================= SMART OCR PARSER =================
  void _parseBlocks(RecognizedText result) {
    result.blocks.sort(
            (a,b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    List<String> lines = [];

    for (final block in result.blocks) {

      for (final line in block.lines) {

        String text = line.text.trim();

        if (text.length > 2) {
          lines.add(text);
        }
      }
    }

    // combine horizontal pairs
    List<String> merged = [];

    for (int i = 0; i < lines.length; i++) {

      if (i < lines.length - 1) {

        String current = lines[i];
        String next = lines[i + 1];

        // merge label + value
        if (current.contains(':') && !next.contains(':')) {
          merged.add("$current $next");
          i++;
          continue;
        }

        // merge common ID labels
        if (current.toLowerCase().contains('name') ||
            current.toLowerCase().contains('father') ||
            current.toLowerCase().contains('dob')) {

          merged.add("$current $next");
          i++;
          continue;
        }
      }

      merged.add(lines[i]);
    }

    _parseText(merged.join('\n'));
  }
  void _parseText(String raw) {

    List<String> lines = raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.length > 2)
        .toList();

    Map<String, String> fields = {};
    List<String> extra = [];
    List<String> nameCandidates = [];

    String documentType = "Identity Document";

    String? personName;
    String? fatherName;

    // ================= STEP 1: BASIC EXTRACTION =================

    for (var line in lines) {

      String l = line.toLowerCase();

      // ================= DOCUMENT DETECTION (ADVANCED INDIA) =================

      final pan = RegExp(r'[A-Z]{5}[0-9]{4}[A-Z]').firstMatch(line);
      if (pan != null) {
        fields["PAN Number"] = pan.group(0)!;
        documentType = "PAN Card";
        continue;
      }


      final aadhaar = RegExp(r'\d{4}\s?\d{4}\s?\d{4}').firstMatch(line);
      if (aadhaar != null) {
        fields["Aadhaar Number"] = aadhaar.group(0)!;
        documentType = "Aadhaar Card";
        continue;
      }

//    ALL INDIA DL FORMAT (VERY IMPORTANT FIX)
      final dl = RegExp(r'[A-Z]{2}[0-9]{2}[\s-]?[0-9]{10,13}').firstMatch(line);
      if (dl != null) {
        fields["Driving License Number"] = dl.group(0)!;
        documentType = "Driving License";
        continue;
      }

// VOTER ID
      final voter = RegExp(r'[A-Z]{3}[0-9]{7}').firstMatch(line);
      if (voter != null) {
        fields["Voter ID Number"] = voter.group(0)!;
        documentType = "Voter ID Card";
        continue;
      }

      // -------- DOB DETECTION --------
      for (int i = 0; i < lines.length; i++) {

        String line = lines[i].toLowerCase();

        // if line contains DOB label
        if (line.contains("dob") ||
            line.contains("d.o.b") ||
            line.contains("date of birth")) {

          final dob = RegExp(r'\d{2}[-/]\d{2}[-/]\d{4}')
              .firstMatch(lines[i]);

          if (dob != null) {

            fields["Date of Birth"] = dob.group(0)!;
            break;

          }

          // check next line if date is separate
          if (i + 1 < lines.length) {

            final dobNext =
            RegExp(r'\d{2}[-/]\d{2}[-/]\d{4}')
                .firstMatch(lines[i + 1]);

            if (dobNext != null) {

              fields["Date of Birth"] = dobNext.group(0)!;
              break;

            }

          }
        }
      }
      // fallback if DOB label not detected
      if (!fields.containsKey("Date of Birth")) {

        List<String> dates = [];

        for (var line in lines) {

          final matches =
          RegExp(r'\d{2}[-/]\d{2}[-/]\d{4}')
              .allMatches(line);

          for (var m in matches) {

            String date = m.group(0)!;

            int year =
            int.parse(date.split(RegExp(r'[-/]'))[2]);

            if (year > 1940 && year < DateTime.now().year) {
              dates.add(date);
            }

          }
        }

        if (dates.isNotEmpty) {

          dates.sort((a, b) {

            int y1 =
            int.parse(a.split(RegExp(r'[-/]'))[2]);

            int y2 =
            int.parse(b.split(RegExp(r'[-/]'))[2]);

            return y1.compareTo(y2);
          });

          fields["Date of Birth"] = dates.first;
        }
      }



      // Gender
      if (l.contains("male")) fields["Gender"] = "Male";
      if (l.contains("female")) fields["Gender"] = "Female";

      // Blood Group
      final blood = RegExp(r'\b(A|B|AB|O)[+-]\b', caseSensitive: false).firstMatch(line);
      if (blood != null) {
        fields["Blood Group"] = blood.group(0)!.toUpperCase();
      }
      // Address
      if (l.contains("vill") ||
          l.contains("village") ||
          l.contains("dist") ||
          l.contains("teh") ||
          l.contains("state") ||
          l.contains("haryana")) {

        fields["Address"] =
            (fields["Address"] ?? "") + " " + line;
        continue;
      }

      // Authority
      if (l.contains("government") ||
          l.contains("india") ||
          l.contains("authority") ||
          l.contains("transport") ||
          l.contains("uidai")) {

        fields["Issuing Authority"] = line;
      }
    }

    // ================= STEP 2: NAME DETECTION =================

    for (int i = 0; i < lines.length; i++) {

      String line = lines[i].toLowerCase();

      if (line.contains("name") &&
          !line.contains("father") &&
          !line.contains("mother")) {

        String? value = _getRightOrBelow(lines, i);

        if (_isValidPersonName(value)) {
          personName = value;
          break;
        }
      }
    }

    // Fallback: ALL CAPS line
    if (personName == null) {

      for (var l in lines) {

        if (l == l.toUpperCase() &&
            _isValidPersonName(l)) {

          personName = l;
          break;
        }
      }
    }
    // Fallback: CAPS
    if (personName == null) {
      for (var l in lines) {
        if (l == l.toUpperCase() && _isValidPersonName(l)) {
          personName = l;
          break;
        }
      }
    }

    // Fallback: line above DOB
    if (personName == null) {

      for (int i = 0; i < lines.length; i++) {

        if (_extractDate(lines[i]) != null && i > 0) {

          String prev = lines[i - 1];

          if (_isValidPersonName(prev)) {
            personName = prev;
            break;
          }
        }
      }
    }

    // ================= STEP 3: FATHER NAME =================

    for (int i = 0; i < lines.length; i++) {

      String original = lines[i];
      String line = original.toLowerCase();


      if (line.contains("father") ||
          line.contains("s/o") ||
          line.contains("d/o") ||
          line.contains("w/o") ||
          line.contains("son of") ||
          line.contains("daughter of")) {

        List<String> candidates = [];

        if (lines[i].contains(":")) {
          candidates.add(lines[i].split(":").last.trim());
        }

        if (i + 1 < lines.length) candidates.add(lines[i + 1]);
        if (i + 2 < lines.length) candidates.add(lines[i + 2]);

        for (var c in candidates) {

          if (_isValidPersonName(c)) {

            // ❗ skip if same as name
            if (personName != null &&
                c.toLowerCase() == personName.toLowerCase()) {
              continue;
            }

            fatherName = c;
            break;
          }
        }

        if (fatherName != null) break; // ❗ STOP after found
      }
    }
    // ❗ If father name == name → remove it
    String name = fields["Name"]?.toString().toLowerCase() ?? "";
    String father = fields["Father Name"]?.toString().toLowerCase() ?? "";

    if (name.isNotEmpty && father.isNotEmpty && name == father) {
      fields.remove("Father Name");
    }
    // ===== EXTRA FATHER NAME DETECTION =====

// Case: "Father Name: XYZ"
    for (int i = 0; i < lines.length; i++) {

      String line = lines[i].toLowerCase();

      if (line.contains("father")) {

        String? value = _getRightOrBelow(lines, i);

        if (value != null && _isValidPersonName(value)) {
          fields["Father Name"] = _formatName(_cleanName(value));
        }
      }
    }

    // ===== FINAL FALLBACK (STRONG) =====
    if (!fields.containsKey("Name")) {

      for (var l in lines) {

        String clean = l.trim();

        if (clean == clean.toUpperCase() &&
            _isValidPersonName(clean)) {

          fields["Name"] = _formatName(_cleanName(clean));
          break;
        }
      }
    }

    // ================= STEP 4: CLEAN + SAVE =================

    if (personName != null) {
      fields["Name"] = _formatName(_cleanName(personName));
    }

    if (fatherName != null && documentType != "PAN Card") {
      fields["Father Name"] = _formatName(_cleanName(fatherName));
    }

    // Remove wrong same values
    if (fields["Name"] != null &&
        fields["Father Name"] != null &&
        fields["Name"]!.toLowerCase() ==
            fields["Father Name"]!.toLowerCase()) {

      fields.remove("Father Name");
    }

    // ================= STEP 5: ADDITIONAL DETAILS =================

    List<String> details = [];

    fields.forEach((key, value) {
      if (key != "Additional Details") {
        details.add("$key : $value");
      }
    });

    // ================= REMOVE GARBAGE =================

    if (details.isNotEmpty) {
      fields["Additional Details"] = details.join("\n");
    }
    fields.removeWhere((key, value) {

      String v = value.toLowerCase();

      return v == "address" ||
          v == "name" ||
          v.contains("road safety") ||
          v.length < 3;
    });

    // ================= STEP 6: SAVE (ONLY ONCE) =================

    if (fields.isNotEmpty) {

      _json.clear();

      _json.addAll({
        "Document Type": documentType,
        ...fields,
      });

      final box = Hive.box('ocr_history');

      box.add({
        "data": Map.from(_json),
        "time": DateTime.now().toString(),
      });
    }
  }

  // ================= HELPERS =================
  int _scoreName(String text) {

    int score = 0;
    String t = text.toLowerCase();

    if (_isValidPersonName(text)) score += 50;

    if (text == text.toUpperCase()) score += 20; // strong signal

    if (t.contains("name")) score += 10;

    if (t.contains("father") || t.contains("address")) score -= 30;

    if (text.split(" ").length == 2 || text.split(" ").length == 3) score += 20;

    return score;
  }
  bool _isInvalidName(String text) {

    String l = text.toLowerCase();

    List<String> invalid = [
      "government",
      "india",
      "transport",
      "authority",
      "licence",
      "license",
      "blood",
      "group",
      "donor",
      "address",
      "issue",
      "valid",
      "date",
      "state",
      "son",
      "daughter",
      "wife",
      "of",
      "birth",
      "dob",
      "tamil",
      "nadu",
      "gujarat",
      "haryana",
      "rajasthan",
      "maharashtra",
      "karnataka",
      "west",
      "bengal",
    ];

    for (var w in invalid) {
      if (l.contains(w)) return true;
    }

    return false;
  }
  bool _isValidPersonName(String? text) {

    if (text == null) return false;

    String t = text.trim();

    if (t.length < 3) return false;

    String lower = t.toLowerCase();

    // ❌ reject numbers
    if (RegExp(r'\d').hasMatch(t)) return false;

    // ❌ reject wrong keywords (VERY IMPORTANT FIX)
    List<String> invalid = [
      "address",
      "village",
      "vill",
      "post",
      "dist",
      "state",
      "india",
      "date",
      "birth",
      "dob",
      "blood",
      "group",
      "organ",
      "donor",
      "licence",
      "license",
      "transport",
      "authority",
      "card",
      "number"
    ];

    for (var w in invalid) {
      if (lower.contains(w)) return false;
    }

    // ❌ reject relation labels
    if (lower.contains("son") ||
        lower.contains("daughter") ||
        lower.contains("wife")) return false;

    // ✅ must be 2–3 words only
    int words = t.split(" ").length;

    if (words < 2 || words > 3) return false;

    return true;
  }

  bool _containsDigit(String s) => RegExp(r'\d').hasMatch(s);

  String? _extractDate(String s) {
    final match =
    RegExp(r'\b\d{2}[-/]\d{2}[-/]\d{4}\b').firstMatch(s);
    return match?.group(0);
  }

  String _formatName(String name) {
    return name
        .toLowerCase()
        .split(" ")
        .map((w) =>
    w.isEmpty ? "" : w[0].toUpperCase() + w.substring(1))
        .join(" ");
  }

  bool isValidName(String line) {

    final l = line.toLowerCase();

    List<String> invalidWords = [
      "india",
      "department",
      "government",
      "authority",
      "commission",
      "transport",
      "licence",
      "license",
      "number",
      "card",
      "name",
      "dob",
      "birth",
      "signature",
      "photo",
      "income",
      "tax",
      "union"
    ];

    if (RegExp(r'\d').hasMatch(line)) return false;

    if (line.split(" ").length > 3) return false;

    for (var w in invalidWords) {
      if (l.contains(w)) return false;
    }

    return line == line.toUpperCase();
  }
  String? _getRightOrBelow(List<String> lines, int index) {

    String current = lines[index];

    // Case 1: value on same line (right side)
    if (current.contains(":")) {

      List<String> parts = current.split(":");

      if (parts.length > 1) {
        return parts[1].trim();
      }
    }

    // Case 2: value written after label
    List<String> words = current.split(" ");

    if (words.length > 1) {

      String possible = words.sublist(1).join(" ").trim();

      if (!_containsDigit(possible) && possible.length > 2) {
        return possible;
      }
    }

    // Case 3: value on next line
    if (index + 1 < lines.length) {

      String next = lines[index + 1].trim();

      if (!_containsDigit(next) &&
          next.split(" ").length >= 2 &&
          !_isInvalidName(next)) {

        return next;
      }
    }

    return null;
  }
  String _cleanName(String name) {

    name = name.replaceAll(RegExp(r'[^A-Za-z\s]'), '');

    // ❗ remove label words (MAIN FIX)
    name = name.replaceAll(RegExp(r'\b(name|father|dob|address)\b', caseSensitive: false), '');

    List<String> words = name.split(" ");

    words.removeWhere((w) =>
    w.trim().isEmpty ||
        w.length < 2 ||
        [
          "of",
          "son",
          "daughter",
          "wife",
          "address",
          "india",
          "group",
          "blood",
          "organ",
          "donor"
        ].contains(w.toLowerCase()));

    return words.join(" ").trim();
  }
  String _cleanAdditionalDetails(List<String> extra) {

    Map<String, String> details = {};

    for (var line in extra) {

      String l = line.toLowerCase();

      // Licence Number
      if (l.contains("licence no") || l.contains("license no")) {
        details["Licence No"] = line.split(":").last.trim();
        continue;
      }

      // Date of Issue
      if (l.contains("doi")) {
        details["Date Of Issue"] = line.split(":").last.trim();
        continue;
      }

      // Valid From
      if (l.contains("valid from")) {

        final match =
        RegExp(r'\d{2}-\d{2}-\d{4}').allMatches(line).toList();

        if (match.length >= 2) {
          details["Valid From"] = match[0].group(0)!;
          details["Valid To"] = match[1].group(0)!;
        }

        continue;
      }

      // Badge number
      if (l.contains("badge")) {
        details["Badge Number"] = line.split(":").last.trim();
        continue;
      }
    }

    if (details.isEmpty) return "";

    return details.entries
        .map((e) => "${e.key} : ${e.value}")
        .join("\n\n");
  }
  Widget _buildFormattedDetails(String text) {

    final lines = text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {

        if (!line.contains(":")) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line),
          );
        }

        final parts = line.split(":");

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              SizedBox(
                width: 160,
                child: Text(
                  parts[0].trim(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold),
                ),
              ),

              const Text(":  "),

              Expanded(
                child: Text(parts.sublist(1).join(":").trim()),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Smart OCR App"),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const HistoryScreen(),
                ),
              );
            },
          )
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [

            Container(
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _image == null
                  ? const Center(child: Text("No image selected"))
                  : Image.file(_image!, fit: BoxFit.cover),
            ),

            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [

                ElevatedButton.icon(
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                  onPressed: () => _pick(ImageSource.camera),
                ),

                ElevatedButton.icon(
                  icon: const Icon(Icons.photo),
                  label: const Text('Gallery'),
                  onPressed: () => _pick(ImageSource.gallery),
                ),

                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Clear'),
                  onPressed: () {
                    setState(() {
                      _image = null;
                      _json.clear();
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 20),

            _json.isEmpty
                ? const Text("No data found")
                : Column(
              children: displayOrder
                  .where((k) => _json.containsKey(k))
                  .map((key) => Container(
                width: double.infinity,
                margin:
                const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      key,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 6),
                    key == 'Additional Details'
                        ? _buildFormattedDetails(
                        _json[key].toString())
                        :Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _json[key].toString(),
                        textAlign: TextAlign.left,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
// ================= HISTORY =================

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box('ocr_history');

    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan History"),
        actions: [

          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: "Clear History",
            onPressed: () {

              final box = Hive.box('ocr_history');

              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Clear History"),
                  content: const Text("Do you want to delete all scan history?"),
                  actions: [

                    TextButton(
                      child: const Text("Cancel"),
                      onPressed: () => Navigator.pop(context),
                    ),

                    TextButton(
                      child: const Text("Delete"),
                      onPressed: () {
                        box.clear();
                        Navigator.pop(context);
                      },
                    ),

                  ],
                ),
              );

            },
          )

        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box box, _) {
          if (box.isEmpty) {
            return const Center(
                child: Text("No history"));
          }

          return ListView.builder(
            itemCount: box.length,
            itemBuilder: (context, index) {
              final item = box.getAt(index);

              return ListTile(
                title: Text(
                    item['data']['Document Type']),
                subtitle:
                Text(item['data']['Name'] ?? ''),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(
                        data: Map<String,
                            dynamic>.from(
                            item['data']),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class DetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const DetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
      AppBar(title: const Text("Scan Details")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: data.entries
            .map((e) =>
            ListTile(
              title: Text(e.key),
              subtitle:
              Text(e.value.toString()),
            ))
            .toList(),
      ),
    );
  }
}



