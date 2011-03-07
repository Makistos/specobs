#!/usr/bin/perl

use FindBin qw($Bin);
use lib $Bin;
use strict;
use warnings;
use File::Find;
use Spec;
use IPC::Open2;

my $specfile;

sub Wanted
{
	/^.\/[^\/]+\.spec$/ or return;
	
	$specfile = $_;
}

# Check that there is no uncommitted work in the work area
my $pid = open2(my $child_out, my $child_in, 'git status --porcelain');

if (<$child_out> ne '') 
{
	print "You have uncommited work in your work directory. Please commit and/or revert them before running this script.\n";
	exit();
}

find({ wanted => \&Wanted, no_chdir => 1}, ".");

my $spec = Spec->new({file => $specfile });

$spec->bump_release();

$spec->remove_patch_info(); # This is a bit crude, we could also send each change as a patch to OBS.

$spec->update();

my @args = ('tar cf' . $spec->tar_compress . ' ' . $spec->compressed_file . ' ' . $spec->fullname);

print (join (" ", @args));

system(@args); 

print "fullname: " . $spec->fullname . "\n";

system("git commit -m \"Updated spec by bump\" -s $specfile");

@args = ("git tag -a \"V" . $spec->version . "-R" . $spec->release . "\"" . " -m \"Upstream v." . $spec->version . " rel." . $spec->release . "\"");

system(@args);

#@args = ("git push --tags");
#system(@args);	

# TODO: Send package to OBS.
