# tk.tcl --
#
# Initialization script normally executed in the interpreter for each
# Tk-based application.  Arranges class bindings for widgets.
#
# RCS: @(#) $Id: tk.tcl,v 1.46.2.2 2004/10/29 11:16:37 patthoyts Exp $
#
# Copyright (c) 1992-1994 The Regents of the University of California.
# Copyright (c) 1994-1996 Sun Microsystems, Inc.
# Copyright (c) 1998-2000 Ajuba Solutions.
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAIMER OF ALL WARRANTIES.

# Insist on running with compatible versions of Tcl and Tk.
package require -exact Tk 8.4
package require -exact Tcl 8.4

# Create a ::tk namespace
namespace eval ::tk {
    # Set up the msgcat commands
    namespace eval msgcat {
	namespace export mc mcmax        
        if {[interp issafe] || [catch {package require msgcat}]} {
            # The msgcat package is not available.  Supply our own
            # minimal replacement.
            proc mc {src args} {
                return [eval [list format $src] $args]
            }
            proc mcmax {args} {
                set max 0
                foreach string $args {
                    set len [string length $string]
                    if {$len>$max} {
                        set max $len
                    }
                }
                return $max
            }
        } else {
            # Get the commands from the msgcat package that Tk uses.
            namespace import ::msgcat::mc
            namespace import ::msgcat::mcmax
            ::msgcat::mcload [file join $::tk_library msgs]
        }
    }
    namespace import ::tk::msgcat::*
}

# Add Tk's directory to the end of the auto-load search path, if it
# isn't already on the path:

if {[info exists ::auto_path] && [string compare {} $::tk_library] && \
	[lsearch -exact $::auto_path $::tk_library] < 0} {
    lappend ::auto_path $::tk_library
}

# Turn off strict Motif look and feel as a default.

set ::tk_strictMotif 0

# Turn on useinputmethods (X Input Methods) by default.
# We catch this because safe interpreters may not allow the call.

catch {tk useinputmethods 1}

# ::tk::PlaceWindow --
#   place a toplevel at a particular position
# Arguments:
#   toplevel	name of toplevel window
#   ?placement?	pointer ?center? ; places $w centered on the pointer
#		widget widgetPath ; centers $w over widget_name
#		defaults to placing toplevel in the middle of the screen
#   ?anchor?	center or widgetPath
# Results:
#   Returns nothing
#
proc ::tk::PlaceWindow {w {place ""} {anchor ""}} {
    wm withdraw $w
    update idletasks
    set checkBounds 1
    if {$place eq ""} {
	set x [expr {([winfo screenwidth $w]-[winfo reqwidth $w])/2}]
	set y [expr {([winfo screenheight $w]-[winfo reqheight $w])/2}]
	set checkBounds 0
    } elseif {[string equal -len [string length $place] $place "pointer"]} {
	## place at POINTER (centered if $anchor == center)
	if {[string equal -len [string length $anchor] $anchor "center"]} {
	    set x [expr {[winfo pointerx $w]-[winfo reqwidth $w]/2}]
	    set y [expr {[winfo pointery $w]-[winfo reqheight $w]/2}]
	} else {
	    set x [winfo pointerx $w]
	    set y [winfo pointery $w]
	}
    } elseif {[string equal -len [string length $place] $place "widget"] && \
	    [winfo exists $anchor] && [winfo ismapped $anchor]} {
	## center about WIDGET $anchor, widget must be mapped
	set x [expr {[winfo rootx $anchor] + \
		([winfo width $anchor]-[winfo reqwidth $w])/2}]
	set y [expr {[winfo rooty $anchor] + \
		([winfo height $anchor]-[winfo reqheight $w])/2}]
    } else {
	set x [expr {([winfo screenwidth $w]-[winfo reqwidth $w])/2}]
	set y [expr {([winfo screenheight $w]-[winfo reqheight $w])/2}]
	set checkBounds 0
    }
    if {[tk windowingsystem] eq "win32"} {
        # Bug 533519: win32 multiple desktops may produce negative geometry.
        set checkBounds 0
    }
    if {$checkBounds} {
	if {$x < 0} {
	    set x 0
	} elseif {$x > ([winfo screenwidth $w]-[winfo reqwidth $w])} {
	    set x [expr {[winfo screenwidth $w]-[winfo reqwidth $w]}]
	}
	if {$y < 0} {
	    set y 0
	} elseif {$y > ([winfo screenheight $w]-[winfo reqheight $w])} {
	    set y [expr {[winfo screenheight $w]-[winfo reqheight $w]}]
	}
	if {[tk windowingsystem] eq "macintosh" \
		|| [tk windowingsystem] eq "aqua"} {
	    # Avoid the native menu bar which sits on top of everything.
	    if {$y < 20} { set y 20 }
	}
    }
    wm geometry $w +$x+$y
    wm deiconify $w
}

# ::tk::SetFocusGrab --
#   swap out current focus and grab temporarily (for dialogs)
# Arguments:
#   grab	new window to grab
#   focus	window to give focus to
# Results:
#   Returns nothing
#
proc ::tk::SetFocusGrab {grab {focus {}}} {
    set index "$grab,$focus"
    upvar ::tk::FocusGrab($index) data

    lappend data [focus]
    set oldGrab [grab current $grab]
    lappend data $oldGrab
    if {[winfo exists $oldGrab]} {
	lappend data [grab status $oldGrab]
    }
    # The "grab" command will fail if another application
    # already holds the grab.  So catch it.
    catch {grab $grab}
    if {[winfo exists $focus]} {
	focus $focus
    }
}

# ::tk::RestoreFocusGrab --
#   restore old focus and grab (for dialogs)
# Arguments:
#   grab	window that had taken grab
#   focus	window that had taken focus
#   destroy	destroy|withdraw - how to handle the old grabbed window
# Results:
#   Returns nothing
#
proc ::tk::RestoreFocusGrab {grab focus {destroy destroy}} {
    set index "$grab,$focus"
    if {[info exists ::tk::FocusGrab($index)]} {
	foreach {oldFocus oldGrab oldStatus} $::tk::FocusGrab($index) { break }
	unset ::tk::FocusGrab($index)
    } else {
	set oldGrab ""
    }

    catch {focus $oldFocus}
    grab release $grab
    if {[string equal $destroy "withdraw"]} {
	wm withdraw $grab
    } else {
	destroy $grab
    }
    if {[winfo exists $oldGrab] && [winfo ismapped $oldGrab]} {
	if {[string equal $oldStatus "global"]} {
	    grab -global $oldGrab
	} else {
	    grab $oldGrab
	}
    }
}

# ::tk::GetSelection --
#   This tries to obtain the default selection.  On Unix, we first try
#   and get a UTF8_STRING, a type supported by modern Unix apps for
#   passing Unicode data safely.  We fall back on the default STRING
#   type otherwise.  On Windows, only the STRING type is necessary.
# Arguments:
#   w	The widget for which the selection will be retrieved.
#	Important for the -displayof property.
#   sel	The source of the selection (PRIMARY or CLIPBOARD)
# Results:
#   Returns the selection, or an error if none could be found
#
if {[string equal $tcl_platform(platform) "unix"]} {
    proc ::tk::GetSelection {w {sel PRIMARY}} {
	if {[catch {selection get -displayof $w -selection $sel \
		-type UTF8_STRING} txt] \
		&& [catch {selection get -displayof $w -selection $sel} txt]} {
	    return -code error "could not find default selection"
	} else {
	    return $txt
	}
    }
} else {
    proc ::tk::GetSelection {w {sel PRIMARY}} {
	if {[catch {selection get -displayof $w -selection $sel} txt]} {
	    return -code error "could not find default selection"
	} else {
	    return $txt
	}
    }
}

# ::tk::ScreenChanged --
# This procedure is invoked by the binding mechanism whenever the
# "current" screen is changing.  The procedure does two things.
# First, it uses "upvar" to make variable "::tk::Priv" point at an
# array variable that holds state for the current display.  Second,
# it initializes the array if it didn't already exist.
#
# Arguments:
# screen -		The name of the new screen.

proc ::tk::ScreenChanged screen {
    set x [string last . $screen]
    if {$x > 0} {
	set disp [string range $screen 0 [expr {$x - 1}]]
    } else {
	set disp $screen
    }

    uplevel #0 upvar #0 ::tk::Priv.$disp ::tk::Priv
    variable ::tk::Priv
    global tcl_platform

    if {[info exists Priv]} {
	set Priv(screen) $screen
	return
    }
    array set Priv {
	activeMenu	{}
	activeItem	{}
	afterId		{}
	buttons		0
	buttonWindow	{}
	dragging	0
	focus		{}
	grab		{}
	initPos		{}
	inMenubutton	{}
	listboxPrev	{}
	menuBar		{}
	mouseMoved	0
	oldGrab		{}
	popup		{}
	postedMb	{}
	pressX		0
	pressY		0
	prevPos		0
	selectMode	char
    }
    set Priv(screen) $screen
    set Priv(tearoff) [string equal [tk windowingsystem] "x11"]
    set Priv(window) {}
}

# Do initial setup for Priv, so that it is always bound to something
# (otherwise, if someone references it, it may get set to a non-upvar-ed
# value, which will cause trouble later).

tk::ScreenChanged [winfo screen .]

# ::tk::EventMotifBindings --
# This procedure is invoked as a trace whenever ::tk_strictMotif is
# changed.  It is used to turn on or turn off the motif virtual
# bindings.
#
# Arguments:
# n1 - the name of the variable being changed ("::tk_strictMotif").

proc ::tk::EventMotifBindings {n1 dummy dummy} {
    upvar $n1 name
    
    if {$name} {
	set op delete
    } else {
	set op add
    }

    event $op <<Cut>> <Control-Key-w>
    event $op <<Copy>> <Meta-Key-w> 
    event $op <<Paste>> <Control-Key-y>
    event $op <<Undo>> <Control-underscore>
}

#----------------------------------------------------------------------
# Define common dialogs on platforms where they are not implemented 
# using compiled code.
#----------------------------------------------------------------------

if {[string equal [info commands tk_chooseColor] ""]} {
    proc ::tk_chooseColor {args} {
	return [eval tk::dialog::color:: $args]
    }
}
if {[string equal [info commands tk_getOpenFile] ""]} {
    proc ::tk_getOpenFile {args} {
	if {$::tk_strictMotif} {
	    return [eval tk::MotifFDialog open $args]
	} else {
	    return [eval ::tk::dialog::file:: open $args]
	}
    }
}
if {[string equal [info commands tk_getSaveFile] ""]} {
    proc ::tk_getSaveFile {args} {
	if {$::tk_strictMotif} {
	    return [eval tk::MotifFDialog save $args]
	} else {
	    return [eval ::tk::dialog::file:: save $args]
	}
    }
}
if {[string equal [info commands tk_messageBox] ""]} {
    proc ::tk_messageBox {args} {
	return [eval tk::MessageBox $args]
    }
}
if {[string equal [info command tk_chooseDirectory] ""]} {
    proc ::tk_chooseDirectory {args} {
	return [eval ::tk::dialog::file::chooseDir:: $args]
    }
}
	
#----------------------------------------------------------------------
# Define the set of common virtual events.
#----------------------------------------------------------------------

switch [tk windowingsystem] {
    "x11" {
	event add <<Cut>> <Control-Key-x> <Key-F20> 
	event add <<Copy>> <Control-Key-c> <Key-F16>
	event add <<Paste>> <Control-Key-v> <Key-F18>
	event add <<PasteSelection>> <ButtonRelease-2>
	event add <<Undo>> <Control-Key-z>
	event add <<Redo>> <Control-Key-Z>
	# Some OS's define a goofy (as in, not <Shift-Tab>) keysym
	# that is returned when the user presses <Shift-Tab>.  In order for
	# tab traversal to work, we have to add these keysyms to the 
	# PrevWindow event.
	# We use catch just in case the keysym isn't recognized.
	# This is needed for XFree86 systems
	catch { event add <<PrevWindow>> <ISO_Left_Tab> }
	# This seems to be correct on *some* HP systems.
	catch { event add <<PrevWindow>> <hpBackTab> }

	trace variable ::tk_strictMotif w ::tk::EventMotifBindings
	set ::tk_strictMotif $::tk_strictMotif
    }
    "win32" {
	event add <<Cut>> <Control-Key-x> <Shift-Key-Delete>
	event add <<Copy>> <Control-Key-c> <Control-Key-Insert>
	event add <<Paste>> <Control-Key-v> <Shift-Key-Insert>
	event add <<PasteSelection>> <ButtonRelease-2>
  	event add <<Undo>> <Control-Key-z>
	event add <<Redo>> <Control-Key-y>
    }
    "aqua" {
	event add <<Cut>> <Command-Key-x> <Key-F2> 
	event add <<Copy>> <Command-Key-c> <Key-F3>
	event add <<Paste>> <Command-Key-v> <Key-F4>
	event add <<PasteSelection>> <ButtonRelease-2>
	event add <<Clear>> <Clear>
  	event add <<Undo>> <Command-Key-z>
	event add <<Redo>> <Command-Key-y>
    }
    "classic" {
	event add <<Cut>> <Control-Key-x> <Key-F2> 
	event add <<Copy>> <Control-Key-c> <Key-F3>
	event add <<Paste>> <Control-Key-v> <Key-F4>
	event add <<PasteSelection>> <ButtonRelease-2>
	event add <<Clear>> <Clear>
	event add <<Undo>> <Control-Key-z> <Key-F1>
	event add <<Redo>> <Control-Key-Z>
    }
}
# ----------------------------------------------------------------------
# Read in files that define all of the class bindings.
# ----------------------------------------------------------------------

if {$::tk_library ne ""} {
    if {[string equal $tcl_platform(platform) "macintosh"]} {
	proc ::tk::SourceLibFile {file} {
	    if {[catch {
		namespace eval :: \
			[list source [file join $::tk_library $file.tcl]]
	    }]} {
		namespace eval :: [list source -rsrc $file]
	    }
	}
    } else {
	proc ::tk::SourceLibFile {file} {
	    namespace eval :: [list source [file join $::tk_library $file.tcl]]
	}	
    }
    namespace eval ::tk {
	SourceLibFile button
	SourceLibFile entry
	SourceLibFile listbox
	SourceLibFile menu
	SourceLibFile panedwindow
	SourceLibFile scale
	SourceLibFile scrlbar
	SourceLibFile spinbox
	SourceLibFile text
    }
}
# ----------------------------------------------------------------------
# Default bindings for keyboard traversal.
# ----------------------------------------------------------------------

event add <<PrevWindow>> <Shift-Tab>
bind all <Tab> {tk::TabToWindow [tk_focusNext %W]}
bind all <<PrevWindow>> {tk::TabToWindow [tk_focusPrev %W]}

# ::tk::CancelRepeat --
# This procedure is invoked to cancel an auto-repeat action described
# by ::tk::Priv(afterId).  It's used by several widgets to auto-scroll
# the widget when the mouse is dragged out of the widget with a
# button pressed.
#
# Arguments:
# None.

proc ::tk::CancelRepeat {} {
    variable ::tk::Priv
    after cancel $Priv(afterId)
    set Priv(afterId) {}
}

# ::tk::TabToWindow --
# This procedure moves the focus to the given widget.  If the widget
# is an entry or a spinbox, it selects the entire contents of the widget.
#
# Arguments:
# w - Window to which focus should be set.

proc ::tk::TabToWindow {w} {
    if {[string equal [winfo class $w] Entry] \
	    || [string equal [winfo class $w] Spinbox]} {
	$w selection range 0 end
	$w icursor end
    }
    focus $w
}

# ::tk::UnderlineAmpersand --
# This procedure takes some text with ampersand and returns
# text w/o ampersand and position of the ampersand.
# Double ampersands are converted to single ones.
# Position returned is -1 when there is no ampersand.
#
proc ::tk::UnderlineAmpersand {text} {
    set idx [string first "&" $text]
    if {$idx >= 0} {
	set underline $idx
	# ignore "&&"
	while {[string match "&" [string index $text [expr {$idx + 1}]]]} {
	    set base [expr {$idx + 2}]
	    set idx  [string first "&" [string range $text $base end]]
	    if {$idx < 0} {
		break
	    } else {
		set underline [expr {$underline + $idx + 1}]
		incr idx $base
	    }
	}
    }
    if {$idx >= 0} {
	regsub -all -- {&([^&])} $text {\1} text
    } 
    return [list $text $idx]
}

# ::tk::SetAmpText -- 
# Given widget path and text with "magic ampersands",
# sets -text and -underline options for the widget
#
proc ::tk::SetAmpText {widget text} {
    foreach {newtext under} [::tk::UnderlineAmpersand $text] {
	$widget configure -text $newtext -underline $under
    }
}

# ::tk::AmpWidget --
# Creates new widget, turning -text option into -text and
# -underline options, returned by ::tk::UnderlineAmpersand.
#
proc ::tk::AmpWidget {class path args} {
    set wcmd [list $class $path]
    foreach {opt val} $args {
	if {[string equal $opt {-text}]} {
	    foreach {newtext under} [::tk::UnderlineAmpersand $val] {
		lappend wcmd -text $newtext -underline $under
	    }
	} else {
	    lappend wcmd $opt $val
	}
    }
    eval $wcmd
    if {$class=="button"} {
	bind $path <<AltUnderlined>> [list $path invoke]
    }
    return $path
}

# ::tk::FindAltKeyTarget --
# search recursively through the hierarchy of visible widgets
# to find button or label which has $char as underlined character
#
proc ::tk::FindAltKeyTarget {path char} {
    switch [winfo class $path] {
	Button -
	Label {
	    if {[string equal -nocase $char \
		[string index [$path cget -text] \
		[$path cget -underline]]]} {return $path} else {return {}}
	}
	default {
	    foreach child \
		[concat [grid slaves $path] \
		[pack slaves $path] \
		[place slaves $path] ] {
		if {""!=[set target [::tk::FindAltKeyTarget $child $char]]} {
		    return $target
		}
	    }
	}
    }
    return {}
}

# ::tk::AltKeyInDialog --
# <Alt-Key> event handler for standard dialogs. Sends <<AltUnderlined>>
# to button or label which has appropriate underlined character
#
proc ::tk::AltKeyInDialog {path key} {
    set target [::tk::FindAltKeyTarget $path $key]
    if { $target == ""} return
    event generate $target <<AltUnderlined>>
}

# ::tk::mcmaxamp --
# Replacement for mcmax, used for texts with "magic ampersand" in it.
#

proc ::tk::mcmaxamp {args} {
    set maxlen 0
    foreach arg $args {
	set length [string length [lindex [::tk::UnderlineAmpersand [mc $arg]] 0]]
	if {$length>$maxlen} {
	    set maxlen $length
	}
    }
    return $maxlen
}
# For now, turn off the custom mdef proc for the mac:

if {[string equal [tk windowingsystem] "aqua"]} {
    namespace eval ::tk::mac {
	set useCustomMDEF 0
    }
}
