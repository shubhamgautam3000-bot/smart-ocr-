# Smart OCR App

Smart OCR App is a powerful and efficient Flutter application designed to extract, parse, and store information from various Indian Identity Documents. By leveraging Google's ML Kit for text recognition, it precisely scans images to detect text and intelligently processes it into structured data.

## Features

- **Document Scanning:** Capture images directly from the Camera or pick existing images from the Gallery.
- **Advanced Text Recognition:** Utilizes **Google ML Kit Text Recognition** for highly accurate results on device.
- **Smart Data Parsing:** Custom RegEx and heuristic-based logic designed specifically to identify formatting and text layouts in Indian ID cards.
- **Supported Documents:**
  - **PAN Card**
  - **Aadhaar Card**
  - **Driving License**
  - **Voter ID Card**
- **Automated Field Extraction:** Automatically extracts key fields such as:
  - Document Type
  - Name
  - Father/Mother Name
  - Date of Birth (DOB)
  - Gender
  - Address
  - Blood Group
  - Unique ID Numbers (PAN/Aadhaar/DL/Voter ID)
  - Issuing Authority
- **Local Persistence & History:** Saves extracted document data securely on your local device using **Hive** (fast local NoSQL database), allowing you to review your scan history any time.

## Tech Stack

- **Framework:** [Flutter](https://flutter.dev/)
- **Language:** Dart
- **Text Recognition:** [Google ML Kit](https://pub.dev/packages/google_mlkit_text_recognition)
- **Local Database:** [Hive](https://pub.dev/packages/hive) & [Hive Flutter](https://pub.dev/packages/hive_flutter)
- **Media & Camera:** [Image Picker](https://pub.dev/packages/image_picker)
- **Permissions:** [Permission Handler](https://pub.dev/packages/permission_handler)

## Getting Started

### Prerequisites
Make sure you have the following installed on your machine:
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version `^3.10.7` or later)
- Dart SDK
- An Android Emulator / iOS Simulator or a physical device connected.

### Installation

1. **Clone the repository** (if applicable) or navigate to the project directory:
   ```bash
   cd smart_ocr_app
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the app:**
   Ensure your device/emulator is running, then execute:
   ```bash
   flutter run
   ```

## Workflow

1. Open the app and grant necessary camera and storage permissions.
2. Select whether to upload an image from the gallery or capture a live photo of a document.
3. The app's Text Recognizer instance parses the raw text from the image.
4. Smart logic sorts text blocks, detects the document type, and extracts key entities (Name, DoB, Father Name, ID numbers).
5. The extracted result is presented in a readable format and saved automatically to the local Hive database `ocr_history` box for future reference.

## Privacy & Security

This application processes all images and text **offline** on the device using Google ML Kit's on-device API. No data is transmitted to external servers, ensuring user privacy and data security. The history of parsed documents is securely stored locally via Hive.
