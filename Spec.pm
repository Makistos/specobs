# Reads info from spec file.
#
# Usage example:
#   use Spec;
#   use File::Find;
#   my $specfile;
#
#   sub Wanted
#   {
#   	/\.spec$/ or return;
#	
#   	$specfile = $_;
#   }

#   find(\&Wanted, ".");
# 	my $spec = Spec->new({file => $specfile });
#   print "Version: $spec->version\n";
# where $specfile = name of .spec file.
#
# Requires Moose, Perl::Version and Switch.

package Spec;

use strict;
use warnings;
use Moose;
use Perl::Version;
use Switch;

my $debug = 0 || $ENV{DEBUG}; # 1 for some additional printing

# Class attributes
has file          => ( is => 'rw', isa => 'Str', required => 1 );
has name          => ( is => 'rw', isa => 'Str' );
has version       => ( is => 'rw', isa => 'Str' );
has epoch	  => ( is => 'rw', isa => 'Str' );
has release       => ( is => 'rw', isa => 'Str' );
has summary       => ( is => 'rw', isa => 'Str' );
has license       => ( is => 'rw', isa => 'Str' );
has group         => ( is => 'rw', isa => 'Str' );
has url           => ( is => 'rw', isa => 'Str' );
has source        => ( is => 'rw', isa => 'ArrayRef[Str]' );
has buildroot     => ( is => 'rw', isa => 'Str' );
has buildarch     => ( is => 'rw', isa => 'Str' );
has buildrequires => ( is => 'rw', isa => 'ArrayRef[Str]' );
has requires      => ( is => 'rw', isa => 'ArrayRef[Str]' );
has patches		  => (is => 'rw', isa =>  'ArrayRef[Str]' );
has fullname	  => (is => 'rw', isa => 'Str' );
has compress	  => (is => 'rw', isa => 'Str' );
has compressed_file => (is => 'rw', isa => 'Str' );
has contents	  => (is => 'rw', isa => 'ArrayRef[Str]' );
has tar_compress  => (is => 'rw', isa => 'Str' );

sub BUILD {
  my $self = shift;

  $self->parse;

  return $self;
}

# Reads the supplied .spec file and saves info to variables.
sub parse
{
  my $self = shift;

  $self->file(shift) if @_;

  my $file = $self->file;
  my $fh;
  @{$self->{patches}} = ();

  open $fh, $file;

  while(<$fh>)
  {  	
  	push @{$self->{contents}}, $_;
	/^Name:\s*(\S+)/		and $self->{name} = 	$1;
	/^Version:\s*(\S+)/ 	and $self->{version} = 	$1;	
	/^Epoch:\s*(\S+)/		and $self->{epoch} = $1;
	/^Release:\s*(\S+)/		and $self->{release} = $1;
	/^Source\d*:\s*(\S+)/	and push @{$self->{source}}, $1;
	/^Patch\d*:\s*(\S+)/		and push @{$self->{patches}}, $1;
	# TODO: Add any fields needed
  }
  for (@{$self->{source}}) {
	# Map tags in file name.
	s/\%\{(\w+)\}/$self->{lc $1} || 
		die "Tag ".lc $1." not found for Source $_"/ge;

	s!http://.*/!!g;

	# Finds the source that is packaged
	if (/^(\S+)\.tar\.(gz|bz2)$/) {
	    (exists $self->{compressed_file} || exists $self->{fullname}) &&
		die "Source tar already parsed: '$self->{compressed_file}'";
	    $self->{compressed_file} = "$_";
	    $self->{fullname} = $1;
	    $self->{compress} = $2;
	    switch ($self->{compress}) {
		case /gz/	{ $self->{tar_compress} = "z"; }
		case /bz2/  	{ $self->{tar_compress} = "j"; }
	    }
	}
  }

  (! exists $self->{fullname} || ! exists $self->{compressed_file}) &&
      die "Source tarball could not be parsed from .spec";

  $debug && do {
  	print "Name: $self->{name}\n";
  	print "Version: $self->{version}\n";
  	print "Relase: $self->{release}\n";
  	print "Compress: $self->{compress}\n";
  	print "Tar-compress: $self->{tar_compress}\n";
  	print "Full name: $self->{fullname}\n";
  	print "Compressed file: $self->{compressed_file}\n";
  	print "Patches: " . join("\n\t", @{$self->{patches}}) . "\n"; 	
  };
  close $fh;
  
  return $self;
}

# Bumps release by one, e.g. 1.1 -> 1.2
sub bump_release
{
	my $self = shift;
	my @tmp_arr;
	for (@{$self->{contents}})
	{
		/^(Release:\s*)(\S+)/		and do {my $version = Perl::Version->new($2);
							$version->version(0) if !$version->version;
											$version->inc_version; 
											push @tmp_arr, "$1$version\n"; 
											$self->{release} = $version;
											print "Release updated to $version.\n"; 
											next;
											}; 
		push @tmp_arr, $_;
	}
	@{$self->{contents}} = @tmp_arr;
}

# Removes the patch lines from the spec file.
sub remove_patch_info
{
	my $self = shift;
	my @tmp_arr;
	
	for (@{$self->{contents}})
	{
		next if /^Patch\d*:(\S+)/;
		push @tmp_arr, $_;
	}
	
	@{$self->{contents}} = @tmp_arr;
}

sub shift_patches
{
	my $self = shift;
	my @tmp_arr;

	my $patch = shift @{$self->{patches}};
	my $patchid = -1;
	
	return undef if !$patch;

	for (@{$self->{contents}})
	{
		if ( /^Patch(\d+):.*$patch/ ) {
			$patchid = $1;
			last;
		}
	}

	if ($patchid != -1) {
		for (@{$self->{contents}}) {
			s/^(Patch$patchid:)/#REMOVED BY IMPORT $1/g;
			s/^(%patch$patchid )/#REMOVED BY IMPORT $1/g;
		}
	}

	return $patch;
}

# Update spec file with current values (i.e. if release has been bumped, this will write new value)
sub update
{
	my $self = shift;
	
	my $file = $self->{file};
	
	open my $out, ">$file";
	print $out @{$self->{contents}};
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
__END__
