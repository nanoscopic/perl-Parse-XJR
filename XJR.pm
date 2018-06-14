#!/usr/bin/perl -w
package Parse::XJR;

use Carp;
use strict;
use vars qw( @ISA @EXPORT @EXPORT_OK $VERSION );
use utf8;
require Exporter;
require DynaLoader;
@ISA = qw(Exporter DynaLoader);
$VERSION = "0.01";
use vars qw($VERSION *AUTOLOAD);

*AUTOLOAD = \&Parse::XJR::AUTOLOAD;
bootstrap Parse::XJR $VERSION;

@EXPORT = qw(read_xjr xjr_to_jsa);
@EXPORT_OK = qw();

=head1 NAME

Parse::XJR - Minimal XML parser implemented via a C state engine

=head1 VERSION

0.01

=cut

sub xjr_to_jsa {
  my $root = Parse::XJR->new( text => shift, mixed => 1 );
  return $root->jsa();
}

sub read_xjr {
  return new( 0, @_ );
}

sub new {
  my $class = shift; 
  my $self  = { isroot => 1, @_ };
  
  my $copyStr = 0;
  if( defined $self->{'file'} ) {
    my $res = open( my $XJR, $self->{ 'file' } );
    if( !$res ) {
      $self->{ 'xjr' } = 0;
      return 0;
    }
    {
      local $/ = undef;
      $self->{'text'} = <$XJR>;
    }
    close( $XJR );
    $copyStr = 1;
  }
  my $mixed = $self->{'mixed'} || 0;
  my $cnode = Parse::XJR::c_parse( $self->{'text'}, $copyStr, $mixed );
  
  my $root = Parse::XJR::Node->new( $cnode );
  $root->makeroot();
  return $root;
}

1;

package Parse::XJR::Node;
use warnings;
use Carp;
use strict;

sub new {
    my ( $class, $cnode ) = @_;
    tie( my %virthash, $class, $cnode );
    return bless \%virthash, $class;
}

sub TIEHASH {
    my ( $class, $cnode ) = @_;
    return bless \$cnode, $class;
}

sub STORE {
    my ( $self, $key, $val ) = @_;
    if( my $rt = ref( $val ) ) {
      if( $rt eq 'HASH' ) {
        c_sethash( $self, $key, $val );
        return;
      }
      if( $rt eq 'ARRAY' ) {
        return;
      }
      return;
    }
    c_setval( $self, $key, $val );
    return $val;
}

sub DESTROY {
    my $self = shift;
    $self->c_free_tree();
}

1;