#!/usr/bin/perl
# Copyright (c) 2003 SuSE GmbH Nuernberg, Germany.  All rights reserved.
#
# Authors:
# --------
# Marcus Schaefer <ms@suse.de>
#
# Perl Skript to update/migrate a XFree86 v3 based system
# into a XOrg 4.x based system
#
# Details:
# --------
# 1) Check if the Card is supported from XOrg 4.x
# 2) Obtain the most important information from the
#    existing 3.x config file
# 3) Create a SaX2 profile with the 3.x data
# 4) Create new 4.x config file with SaX2
#    - use real driver if supported
#    - use fbdev driver if card is framebuffer capable
#    - use vesa driver if vesa BIOS was found
#    - use vga driver if no VESA bios was found
#
# Status: Up-To-Date
#
#----[ readFile ]----#
sub readFile {
#----------------------------------------------
# read the XFree86_3x based configuration file
# and save the lines in a list. Check for a
# valid SaX(1) header
#
	my @result = ();
	my $infile = "/etc/XF86Config";
	open (FD,$infile) || die "Update::Could not open input file";
	my $header = <FD>;
	if ($header !~ /# SaX autogenerated/) {
		die "Update::Not a SaX(1) header";
	}
	while (<FD>) {
		chomp $_; push @result,$_;
	}
	return @result;
}

#---[ getDefaultColor ]---#
sub getDefaultColor {
#----------------------------------------------
# obtain default color depth
#
	my $depth = 8;
	foreach (@_) {
	if ($_ =~ /DefaultColorDepth(.*)/) {
		$depth = $1;
		$depth =~ s/\s+//g;
		if ($depth < 8) {
			$depth = 16;
		}
		return $depth;
	}
	}
	return undef;
}

#---[ getModeForColor ]---#
sub getModeForColor {
#----------------------------------------------
# obtain Modes line used for given color depth
#
	my $color = $_[0];
	my @list  = @{$_[1]};
	my $start = 0;
	foreach (@list) {
	if ($_ =~ /^\s+Depth\s+$color/) {
		$start = 1;
		next;
	}
	if (($start) && ($_ =~ /Modes\s+(.*)/)) {
		my $modes = $1;
		$modes =~ s/\s+$//;
		$modes =~ s/\"//g;
		$modes =~ s/\s+/,/g;
		return $modes;
	}
	}
	return undef;
}

#---[ getSyncRange ]---#
sub getSyncRange {
#----------------------------------------------
# obtain sync ranges from Monitor section
#
	my %result;
	foreach (@_) {
	if ($_ =~ /^\s+HorizSync\s+(.*)/) {
		my $hsync = $1;
		$hsync =~ s/\s+//g;
		$result{HSync} = $hsync;
	}
	if ($_ =~ /^\s+VertRefresh\s(.*)/) {
		my $vsync = $1;
		$vsync =~ s/\s+//g;
		$result{VSync} = $vsync;
	}
	}
	if ((defined $result{HSync}) && (defined $result{VSync})) {
		return %result;
	}
	return undef;
}

#---[ isSupported ]---#
sub isSupported {
#-------------------------------------------------
# check if the card is supported from XOrg 4.x
#
	my $class = "Unclassified";
	my $sysp  = "/usr/X11R6/lib/sax/sysp.pl -c";
	my $data  = qx ($sysp);
	if (grep (/$class/,$data)) {
		return 0;
	}
	return 1;
}

#=======================================
# Main...
#---------------------------------------
if ($< != 0) {
	die "Update::Only root can do this";
}
my @list  = readFile();
my $color = getDefaultColor (@list);
my $mode  = getModeForColor ($color,\@list);
my %sync  = getSyncRange (@list);

#=======================================
# Printout...
#---------------------------------------
my $profile = "/var/cache/sax/files/updateProfile";
open (FD,">$profile")
	|| die "Update::Couldn't create file: $profile: $!";
if (defined $color) {
	print FD "Screen->0->DefaultDepth = $color\n";
}
if (defined $mode) {
	print FD "Screen->0->Depth->$color->Modes = $mode\n";
}
if (defined %sync) {
	print FD "Monitor->0->HorizSync = $sync{HSync}\n";
	print FD "Monitor->0->VertRefresh = $sync{VSync}\n";
}

#=======================================
# Generate/Merge config file...
#---------------------------------------
if (isSupported()) {
	#============================================
	# 1) Card is supported...
	#--------------------------------------------
	close FD;
	qx (sax2 -r -a -b $profile);
	exit 0;
}
if (open (FB,"/dev/fb0")) {
	#============================================
	# 2) Card not supported but fbdev capable
	#--------------------------------------------
	close FB;
	close FD;
	# YaST should InjectFile() the fbdev config file...
	exit 1;
}
my $bios = qx (hwinfo --bios | grep "VESA BIOS");
if ($bios =~ /VESA BIOS/) {
	#============================================
	# 3) Card not fbdev capable but VESA capable
	#--------------------------------------------
	print FD "Desktop->0->CalcModelines = no\n";
	print FD "Monitor->0->CalcAlgorithm = XServerPool\n";
	print FD "Desktop->0->Modelines\n";
	close FD;
	qx (sax2 -m 0=vesa -a -b $profile);
	exit 2;
} else {
	#============================================
	# 4) Card is not VESA capable -> vga
	#--------------------------------------------
	close FD;
	qx (sax2 -m 0=vga -a);
	exit 3;
}
