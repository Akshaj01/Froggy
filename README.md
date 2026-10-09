# Froggy

A tiny anime-style frog for the Mac menu bar. Drag its tongue onto a file to make a PDF, double-click it to screenshot the screen, and click it to choose where those files are saved.

The frog sits at the top of the screen, just to the right of the camera notch.

## Use it

- **Drag** from the frog onto a file in Finder or on the Desktop. The tongue stretches in a straight line to the cursor. Let go and Froggy saves a PDF.
- **Double-click** the frog to save a PNG screenshot of that display.
- **Click once** to open the menu: see the current folder, change it, open it, or quit.

New files go to `~/Documents/Froggy` until you pick another folder. That choice is remembered.

Images, existing PDFs, text, Markdown, HTML, RTF, and Word files become PDFs. Folders, apps, and video get a short “can’t make a PDF of that” message.

## Permissions

macOS asks the first time you use each action:

- **Accessibility**, so the tongue can tell which file is under the cursor.
- **Screen Recording**, so a double-click can capture the display.

## Run it

You need Xcode or the Swift toolchain on macOS 14 or later.

```bash
./Scripts/package-app.sh
open Froggy.app
```

The frog stays up until you choose Quit. There is no Dock icon.
