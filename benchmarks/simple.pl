#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Benchmark qw(:all);

use Mouse::Util::TypeConstraints;

package FDP::Form {
    use Form::Data::Processor::Mouse;
    extends 'Form::Data::Processor::Form';

    has_field text => (
        type           => 'Text',
        not_resettable => 1,
    );

    has_field text_required => (
        type           => 'Text',
        required       => 1,
        not_resettable => 1,
    );

    has_field text_min => (
        type           => 'Text',
        minlength      => 10,
        not_resettable => 1,
    );

    has_field text_max => (
        type           => 'Text',
        maxlength      => 10,
        not_resettable => 1,
    );

    sub validate_text_max {
        my $self  = shift;
        my $field = shift;

        return if $field->has_errors;

        $field->add_error('validate_text_max')
            if ( $field->value || '' ) =~ /try/;
    }
}

package HFH::Form {
    use HTML::FormHandler::Mouse;
    extends 'HTML::FormHandler';

    has_field text => ( type => 'Text', );

    has_field text_required => (
        type     => 'Text',
        required => 1,
    );

    has_field text_min => (
        type      => 'Text',
        minlength => 10,
    );

    has_field text_max => (
        type      => 'Text',
        maxlength => 10,
    );

    sub validate_text_max {
        my $self  = shift;
        my $field = shift;

        return if $field->has_errors;

        $field->add_error('validate_text_max')
            if ( $field->value || '' ) =~ /try/;
    }
}

package main {
    my ( $fdp, $hfh );

    cmpthese(
        -5,
        {
            'Create Form::Data::Processor' => sub {
                $fdp = FDP::Form->new();

            },
            'Create HTML::FormHandler' => sub {

                $hfh = HFH::Form->new();
            },
        }
    );


    my $data = {
        text          => 'The text' x 1024,
        text_required => 'The required text' x 512,
        text_min      => 'minimum' x 10,
        text_max      => 'x' x 10,
    };

    cmpthese(
        -5,
        {
            'Form::Data::Processor' => sub {
                die 'Form::Data::Processor: validate error' unless $fdp->process($data);
            },
            'HTML::FormHandler' => sub {
                die 'HTML::FormHandler: validate error' unless $hfh->process($data);
            },
        }
    );
}

=head1 RESULTS

Intel(R) Core(TM)2 Duo CPU E4600  @ 2.40GHz,4GB, OpenSuSE, Linux 3.11.6-4-pae (e6d4a27) i686

                                  Rate Create HTML::FormHandler Create Form::Data::Processor
    Create HTML::FormHandler     100/s                       --                         -78%
    Create Form::Data::Processor 455/s                     353%                           --

                            Rate     HTML::FormHandler Form::Data::Processor
    HTML::FormHandler      378/s                    --                  -79%
    Form::Data::Processor 1774/s                  369%                    --

=cut
