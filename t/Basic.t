#!/usr/bin/perl -w

use strict;

use Test::More qw(no_plan);

use_ok( 'Parse::XJR' );

{
    my $root = reparse( "<xml><node>val</node></xml>" );
    is( $root->{xml}->{node}->value(), 'val', 'normal node value reading' );
}

{
    my $root = reparse( "<xml><node/></xml>" );
    is( defined( $root->{xml}->{node} ), 1, 'existence of blank node' );
}

{
    my $root = reparse( "<xml><node att=12>val</node></xml>" );
    is( $root->{xml}->{node}->{att}->value(), '12', 'reading of attribute value' );
}

{
    my $root = reparse( "<xml><node att=\"12\">val</node></xml>" );
    is( $root->{xml}->{node}->{att}->value(), '12', 'reading of " surrounded attribute value' );
}

{
    my $root = reparse( "<xml><node .att>val</node></xml>" );
    #$root->dump(10);
    #print STDERR "xjr:".$root->xjr();
    
    # TODO. Should work. Doesn't.
    #is( $root->{xml}{node}->hasflag("att"), '1', "reading of value of standalone attribute" );
    
    is( $root->{xml}{node}{att}->isflag(), 1, "can check for a flag" );
}

{
    my $root = reparse( "<xml><node><![CDATA[<cval>]]></node></xml>" );
    #print STDERR "xjr:".$root->xjr();
    is( $root->{xml}->{node}->value(), '<cval>', 'reading of cdata' );
}

{
    my $root = reparse( "<xml><node>a</node><node>b</node></xml>" );
    is( $root->{xml}->{'@node'}->[1]->value(), 'b', 'multiple node array creation' );
}

# Note that reparse of mixed does not work since xjr adds spaces
{
    my $root = Parse::XJR->new( text => "<xml><node>v1<a/>v2</node></xml>", mixed => 1 );
    is( $root->{xml}->{node}->{'@_'}->[0]->value(), 'v1', 'mixed; first value' );
    is( $root->{xml}->{node}->{'@_'}->[1]->value(), 'v2', 'mixed; second value' );
    #is( $root->{xml}->{_}->value(), 'val', 'basic mixed - value before' );
}

# Cannot reparse; since xjr output dropped these sort of mixed values
{
    my $root = Parse::XJR->new( text => "<xml><node><a/>val</node></xml>" );
    is( $root->{xml}->{node}->value(), 'val', 'basic mixed - value after' );
}

{
    my $root = Parse::XJR->new( text => "<xml><node><a/>val</node></xml>" );
    is( $root->{xml}->{node}->value(), 'val', 'basic mixed - value after' );
}

{
    my $root = reparse( "<xml><!--test--></xml>",1  );
    is( $root->{xml}->{_comment}->value(), 'test', 'loading a comment' );
}

# test node addition
{
    my $root = Parse::XJR->new( text => "<xml></xml>" );
    $root->{xml}{item} = { name => 'bob' };
    is( $root->{xml}{item}{name}->value(), 'bob', 'node addition' );
    my $xml = $root->xjr();
    $root = Parse::XJR->new( text => $xml );
    is( $root->{xml}{item}{name}->value(), 'bob', 'node addition reparsed' );
}

# test parsing xjr onto
{
    my $root = Parse::XJR->new( text => "<xml></xml>" );
    $root->{xml}->parse("<item name='bob'/>");
    is( $root->{xml}{item}{name}->value(), 'bob', 'node addition via parse' );
    my $xml = $root->xjr();
    $root = Parse::XJR->new( text => $xml );
    is( $root->{xml}{item}{name}->value(), 'bob', 'node addition via parse reparsed' );
}

# test accessing nodes in order
{
    my $root = Parse::XJR->new( text => "<a n='10'/><b n='20'/><a n='30'/>" );
    #$root->dump(20);
    my $n1 = $root->firstChild();
    is( $n1->name(), 'a', 'nodes in order; 1' );
    is( $n1->{n}->value(), 10, 'nodes in order; 1 - value' );
    my $n2 = $n1->next();
    is( $n2->name(), 'b', 'nodes in order; 2' );
    is( $n2->{n}->value(), 20, 'nodes in order; 2 - value' );
    my $n3 = $n2->next();
    is( $n3->name(), 'a', 'nodes in order; 3' );
    is( $n3->{n}->value(), 30, 'nodes in order; 3 - value' );
}

{
    my $root = Parse::XJR->new( text => "<a/>" );
    my $a = $root->firstChild();
    $a->{n} = 10;
    is( $a->{n}->value(), 10, 'able to add a value' );
}

# test cyclic equalities
cyclic( "<xml><b><!--test--></b><c/><c/></xml>", 'comment' );
cyclic( "<xml><a><![CDATA[cdata]]></a></xml>", 'cdata' ); # with cdata

# TODO support _i and _z
#my $text = '<xml><node>checkval</node></xml>';
#$root = Parse::XJR->new( text => $text );
#my $i = $root->{'xml'}{'node'}{'_i'}-1;
#my $z = $root->{'xml'}{'node'}{'_z'}-$i+1;
#is( substr( $text, $i, $z ), '<node>checkval</node>', '_i and _z vals' );

# saving test
#$root = Parse::XJR->new( file => 't/test.xml' );
# TODO implement save
#$root->save();
#$root->test();

0;

sub reparse {
  my $root = Parse::XJR->new( text => shift );
  my $a = $root->xjr();
  #print STDERR "xjr = $a\n";
  return Parse::XJR->new( text => $a );
}

sub cyclic {
  my ( $text, $name ) = @_;
  my $root = Parse::XJR->new( text => $text );
  my $a = $root->xjr();
  $root = Parse::XJR->new( text => $a );
  my $b = $root->xjr();
  is( $a, $b, "cyclic - $name" );
}
