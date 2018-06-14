#!/usr/bin/perl
use ExtUtils::MakeMaker;
require 5.006;
my @basics = ( 
    AUTHOR       => 'David Helkowski <cpan@codechild.com>',
    ABSTRACT     => 'XMLish JSONish Ragel Powered Parser.',
    NAME         => 'Parse::XJR',
    VERSION_FROM => 'XJR.pm',
    XSOPT        => '-nolinenumbers', # line number defines were causing issues on some platforms
    BUILD_REQUIRES => {
        'English' => 0
    },
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.30'
    },
    PREREQ_PM => {
        Carp => 0,
        DynaLoader => 0,
        Exporter => 0
    },
    OBJECT => 'XJR.o',
);

my $cc = getcc();
if( $cc ) {
  push( @basics, CC => $cc );
}
if( $ExtUtils::MakeMaker::VERSION >= 6.31 ) {
  push( @basics, LICENSE => 'perl' );
}

if( $^O eq 'MSWin32' && !$cc ) {
  gen_msvc(); # special case for msvc
}
elsif( $^O eq 'darwin' ) {
  gen_darwin();
}
elsif( $^O eq 'solaris' ) {
  gen_solaris();
}
else {
  gen_cc(); # all others
}
sub gen_msvc {
  require Config;
  my $libpath = Config->{'archlibexp'};
  my $ver = $]*1000000;
  my $sub = $ver % 1000;
  $ver -= $sub;
  $ver /= 1000;
  my $minor = $ver % 1000;
  $ver -= $minor;
  my $major = $ver / 1000;
  WriteMakefile( @basics,
    CCFLAGS   => "/MT /DWIN32 /TP /DNOSTRING",
    LIBS      => ["$libpath\\core\\perl$major$minor.lib"],# Todo; add XJR lib here
    LDDLFLAGS => '/DLL /NODEFAULTLIB:libcmt',
    #OPTIMIZE  => '-Zl -DNDEBUG -O1', # Because -MD is included by default BLEH
  );
}
sub gen_cc {
  WriteMakefile( @basics,
    LIBS      => ['-lm -lxjr'],
    LDDLFLAGS => '-shared -L/usr/local/lib',
    CCFLAGS   => '-I/usr/local/include',
  );
}
sub gen_solaris {
  WriteMakefile( @basics,
    LIBS      => ['-lm -lxjr'],
    LDDLFLAGS => '-G -L/usr/local/lib', # -G is equiv of -shared
    CCFLAGS   => '-I/usr/local/include',
  );
}
sub gen_darwin {
  if( substr(`which gcc`,0,2) eq 'no' ) {
    print "XCode must be installed.\n";
    exit 1;
  }
  WriteMakefile( @basics,
    LIBS      => ['-lm -lxjr'],
    CCFLAGS   => "-dynamiclib -DDARWIN -fno-common -I/usr/local/include",
    LDDLFLAGS => '',
  );
}
sub getcc {
  my $div = (substr($ENV{'PATH'},0,1) eq '/') ? ':' : ';';
  my @path = split($div,$ENV{'PATH'});
  foreach my $dir ( @path ) {
    return 'gcc' if( -e "$dir/gcc" || -e "$dir/gcc.exe" ); # prefer gcc
    return 'cc'  if( -e "$dir/cc"  || -e "$dir/cc.exe"  );
  }               
  return 0;
}

# The following are hacks to force static linking and so remove need for msvcr## dll
package MY;

sub cflags {
  my $res = shift->SUPER::cflags( @_ );
  if( $^O eq 'MSWin32' ) {
    $res =~ s/-O1/-O2/g;
    $res =~ s/-MD/-MT/g;
  }
  return $res;
}

sub const_loadlibs {
  my $res = shift->SUPER::const_loadlibs( @_ );
  if( $^O eq 'MSWin32' ) {
    $res =~ s/msvcrt\.lib/libcmt\.lib/gi;
  }
  return $res;
}

