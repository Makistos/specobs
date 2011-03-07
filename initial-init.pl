#!/usr/bin/perl

# The initial (empty) repo must exist and this script must be run in that repo

# Usage:
# 1. Create the empty repo to GitWeb.
# 2. Clone this repo to your comp.
# 3. Get the component package file (*.rpm) and unpack (rpm2cpio | cpio -idm) this to local repo dir.
# 4. Run this script in the local repo dir.

use FindBin qw($Bin);
use lib $Bin;
use strict;
use warnings;
use File::Find;
use File::Path;
use Spec;

my $specfile;

sub git_commit
{
	my $msg = shift;
	my @git_args = ("git add .");
	system(@git_args);
	@git_args = ("git commit -m \"". $msg . "\"");
	system(@git_args);
}

sub apply_patch
{
	my ($patch_name, $dir) = @_;
	chdir $dir;
	my @args = ("patch -p1 < ../" . $patch_name); 
	system(@args);
	chdir "..";
}

sub Wanted
{
	/\.spec$/ or return;
	
	$specfile = $_;
}

find(\&Wanted, ".");

my $spec = Spec->new({file => $specfile });

-e ".git" || die "Not a git repo and could not create one (permissions?)!\n";

if (! -e $spec->fullname)
{
  -e $spec->compressed_file || die "No sources found!\n";	

  my @args = ("tar", "xfv" . $spec->tar_compress, $spec->compressed_file);
  system(@args) == 0 or die "Failed to unpack sources!\n";
  system("chmod a+wrx " . $spec->fullname);
  # Remove git repo from source package.
  -e $spec->fullname . "/.git" and rmtree ([$spec->fullname . "/.git"]);

  unlink $spec->compressed_file; # We don't want to store the compressed file to our vcs
}

my $commit_msg = "Initial commit for " . $spec->name;
git_commit($commit_msg);
my $patch;
while(my $patch = $spec->shift_patches())
{
	apply_patch($patch, $spec->fullname);
	$spec->update();
	$patch =~ /(.+)\.patch$/ and $commit_msg = "Patched " . $spec->name . " with " . $1 . "\n";
	git_commit($commit_msg);	
}

# Tag 'em and bag 'em

my @git_args = ("git tag -a upstream -m \"Upstream v." . $spec->version . " rel." . $spec->release . "\"");
system(@git_args);

@git_args = ("git push origin master");
system(@git_args);	

@git_args = ("git push --tags");
system(@git_args);	
