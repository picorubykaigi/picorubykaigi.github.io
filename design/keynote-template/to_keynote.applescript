-- Open the generated .pptx in Keynote, save it as .key and export slide images
-- for checking. Usage: osascript to_keynote.applescript <in.pptx> <out.key> <image dir>
on run argv
	set pptxPath to POSIX file (item 1 of argv)
	set keyPath to POSIX file (item 2 of argv)
	set imageDir to POSIX file (item 3 of argv)
	tell application "Keynote"
		set doc to open pptxPath
		delay 2
		save doc in keyPath
		export doc to imageDir as slide images with properties {image format:PNG, skipped slides:false}
		close doc saving no
	end tell
end run
