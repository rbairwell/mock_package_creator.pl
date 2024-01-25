#!perl

=encoding utf8

=head1 NAME

mock_package_creator.pl - Very simple and crude script to make a mock package

=head1 DESCRIPTION

I needed to be able to create a couple of packages for testing purposes which would
inherit any public methods from a defined package (but allow them to be re-written)
and ensure all access to private methods are blocked. This script does that job.

It's not pretty, it's not really been tested, it probably has a few bugs in it -
but it does/did what I needed it to do: and I think it may be useful for other people
as well.

=head1 SYNOPSIS

    perl mock_package_creator.pl My::Package::In::Lib

=cut

use v5.20.0;
use strict;
use warnings;
use vars;
use utf8;
use File::Basename qw/dirname/;
use File::Spec();
use PPI;

use Carp    qw/carp croak/;
use autodie qw/:all/;
use feature qw/signatures/;
no if $] >= 5.032, q|feature|, qw/indirect/;
no warnings qw/experimental::signatures/;

if ( scalar(@ARGV) != 1 ) {
    print "\n" . sprintf( 'Usage %s Perl::PackageName::To::Read', $0 );
    print "  VERY CRUDE script to read a Perl PackageName (from ./lib/ ) and then make a very\n";
    print "  basic 'mock' package to aid in testing. You probably do need to need to modify this\n";
    print "  script to meet your own requirements.\n";
    exit;
}

my $package_name = $ARGV[0];
chomp($package_name);
print sprintf( 'Processing package %s', $package_name ) . "\n";
my $package_path     = File::Spec->catdir( File::Basename::dirname( File::Spec->rel2abs(__FILE__) ), q/lib/ );
my $package_filename = ( $package_name =~ tr{:}{\/}rs ) . '.pm';
my $full_filename    = File::Spec->catfile( $package_path, $package_filename );
print sprintf( 'Loading "%s"', $full_filename ) . "\n";
my $ppi = PPI::Document->new( $full_filename, 'readonly' => 1 );

if ( !defined($ppi) ) {
    croak( sprintf( 'Unable to load "%s": "%s"', $full_filename, PPI::Document::errstr() ) );
}

my $parent_packagename = $ppi->find_first('PPI::Statement::Package')->namespace;
print sprintf( 'Got parent package name "%s"', $parent_packagename ) . "\n";
my ( @output, @privates );
if ( $parent_packagename =~ /\A(.+)::([^:]+)\z/ ) {
    push @output, _make_prelude( $parent_packagename, $1, $2 );
}
else {
    croak('Package name cannot be split!');
}

# Find all the named subroutines
my $subnodes = $ppi->find( sub { $_[1]->isa('PPI::Statement::Sub') && $_[1]->name } );

for my $subnode ( @{$subnodes} ) {
    my $subname = $subnode->name;
    if ( !$subname ) {
        next;
    }
    my $prototype = $subnode->prototype;
    if ( index( $subname, '_' ) == 0 ) {
        if ( $prototype eq q{} ) {
            $prototype = q{ };
        }
        else {
            $prototype = sprintf( ' %s ', $prototype =~ s/,/, /gr );
        }
        push @privates, _make_private_sub( $subname, $prototype );
    }
    else {
        if ( $prototype =~ /\A(\$self|\$class)(,(.*))?\z/ ) {
            my ( $selfreference, $others ) = ( $1, $3 || q{} );
            if ( $others ne q{} ) {
                $others = sprintf( ' %s ', $others );
            }

            push @output,
              _make_public_method( $subname, $prototype =~ s/,/, /gr, $selfreference, $others =~ s/,/, /gr );
        }
        else {
            if ( $prototype eq q{} ) {
                $prototype = q{ };
            }
            else {
                $prototype = sprintf( ' %s ', $prototype =~ s/,/, /gr );
            }
            push @output, _make_public_sub( $subname, $prototype, $parent_packagename );
        }
    }
}
if ( scalar(@privates) > 0 ) {
    push @output, '# Private subroutines - should not be called.' . "\n"
      . '## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)' . "\n";
    push @output, @privates;
}
push @output, _make_postlude();

# send the output!
print "\n" . join( "\n", @output );

sub _make_postlude() {
    return <<"END_POSTLUDE";
1;
END_POSTLUDE
}

sub _make_prelude ( $parent, $start, $end ) {
    return <<"END_PRELUDE";
package ${start}::Tests::Mock${end};
use strict;
use warnings;
use File::Basename qw/dirname/;
use File::Spec();
use lib File::Spec->catdir(
    File::Basename::dirname( File::Spec->rel2abs(__FILE__) ),
    ( File::Spec->updir() ) x 4,
    qw/lib/
);    # set path to our modules
use parent  qw/${parent_packagename}/;
use Carp    qw/carp croak/;
use feature qw/signatures/;
no warnings qw/experimental::signatures/;

# Public routines - should be overriden.
END_PRELUDE
}

sub _make_public_method ( $subname, $prototype, $selfreference, $others ) {
    return <<"END_SUB";
sub ${subname} ( ${prototype} ) {
    return ${selfreference}->SUPER::${subname}(${others});
}
END_SUB
}

sub _make_public_sub ( $subname, $prototype, $parent_packagename ) {
    return <<"END_SUB";
sub ${subname} ($prototype) {
    return ${parent_packagename}::${subname}(${prototype});
}
END_SUB
}

sub _make_private_sub ( $subname, $prototype ) {
    return <<"END_SUB";
sub ${subname} ($prototype) {
    croak('Private subroutine %s should not be called','${subname}');
}
END_SUB
}

__END__

=head1 AUTHORS

=over 4

=item Richard Bairwell E<lt>rbairwell@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2023 Richard Bairwell E<lt>rbairwell@cpan.orgE<gt>

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. The full text
of this license can be found in the F<LICENSE> file
included with this module.

See F<http://dev.perl.org/licenses/>

=cut
