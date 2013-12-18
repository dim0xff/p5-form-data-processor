use strict;
use warnings;

use utf8;

use Test::More;
use Test::Exception;

use FindBin;
use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

use Moose::Util::TypeConstraints;

package Form::Role::Ready {
    use Form::Data::Processor::Moose::Role;

    has ready_cnt => (
        is      => 'rw',
        isa     => 'Int',
        traits  => ['Number'],
        default => 0,
        handles => {
            add_ready_cnt => 'add',
        }
    );

    sub ready {
        shift->add_ready_cnt(1);
    }
}

package Form::TraitFor::Text {
    use Form::Data::Processor::Moose::Role;

    apply [
        {
            transform => sub {
                my $v = shift;
                $v =~ s/\s+/ /igs;
                return $v;
            },
        }
    ];
}

package Form::Field::TextCompound {
    use Form::Data::Processor::Moose;
    extends 'Form::Data::Processor::Field::Compound';

    has_field text => ( type => 'Text', );

    has_field text_max => (
        type      => 'Text',
        maxlength => 10,
        traits    => [ 'Form::TraitFor::Text', 'Form::Role::Ready' ],
    );
}

package Form {
    use Form::Data::Processor::Moose;

    extends 'Form::Data::Processor::Form';
    with 'Form::Role::Ready';

    has_field 'compound' => (
        type   => 'Compound',
        traits => ['Form::Role::Ready'],
    );

    has_field 'compound.text' => (
        type     => 'Text',
        required => 1,
        traits   => ['Form::Role::Ready'],
    );

    has_field 'compound.text_min' => (
        type      => 'Text',
        minlength => 10,
        traits    => ['Form::Role::Ready'],
    );

    has_field 'compound.compound' => ( type => '+Form::Field::TextCompound', );

    sub dump_errors {
        return { map { $_->full_name => [ $_->all_errors ] }
                shift->all_error_fields };
    }
}

package main {
    my $form = Form->new();

#<<<
    subtest 'ready()' => sub {
        is( $form->ready_cnt,                                       1, 'FDP::Form ready' );
        is( $form->field('compound')->ready_cnt,                    1, 'FDP::Field ready' );
        is( $form->field('compound.text')->ready_cnt,               1, 'FDP::Field::Compound 1/3 ready' );
        is( $form->field('compound.text_min')->ready_cnt,           1, 'FDP::Field::Compound 2/3 ready' );
        is( $form->field('compound.compound.text_max')->ready_cnt,  1, 'FDP::Field::Compound 3/3 ready' );

    };
#>>>

    subtest 'reset()' => sub {
        $form->field('compound.compound.text_max')->disabled(1);
        $form->reset_fields();
        ok( !$form->field('compound.compound.text_max')->disabled,
            'Field is not disabled after reset' );

        $form->field('compound')->required(1);
        $form->field('compound')->not_resettable(1);
        ok( !$form->process( { compound => undef, } ),
            'Form validated with errors' );
        is_deeply(
            $form->dump_errors,
            { compound => ['Field is required'] },
            'Field is required message'
        );

        ok( !$form->process( { compound => '', } ),
            'Form validated with errors' );
        is_deeply(
            $form->dump_errors,
            { compound => ['Field is invalid'] },
            'Field is invalid message on ""'
        );

        $form->field('compound')->required(0);
        $form->field('compound')->not_resettable(0);
        ok( !$form->process( { compound => undef, } ),
            'Form validated with errors' );
        is_deeply(
            $form->dump_errors,
            { compound => ['Field is invalid'] },
            'Field is invalid on undef'
        );
    };

    subtest 'has_fields_errors' => sub {
        $form->clear_errors;
        $form->field('compound.compound')->add_error('invalid');
        ok( $form->has_fields_errors, 'Form has fields errors' );
        ok( $form->has_errors,        'Form has errors' );

        $form->clear_errors;
        $form->add_error('invalid');
        ok( !$form->has_fields_errors, 'Form does not have fields errors' );
        ok( $form->has_errors,         'Form has errors' );

        ok( $form->process( {} ),
            'Form validated without errors on empty input' );
    };

    ok( !$form->process( { compound => {} } ), 'Form validated with errors' );
    is_deeply(
        $form->dump_errors,
        { 'compound.text' => ['Field is required'] },
        'Correct error messages'
    );

    my $data = {
        compound => {
            text     => 'text   text',
            text_min => 'text',
            compound => {
                text_max => '   text   ' x 10,
            },
        }
    };
    ok( !$form->process($data), 'Form validated with errors' );
    is_deeply(
        $form->dump_errors,
        {
            'compound.text_min'          => ['Field is too short'],
            'compound.compound.text_max' => ['Field is too long'],
        },
        'Correct error messages'
    );

    $data->{compound}{compound}{text_max} =~ s/^\s+|\s+$//igs;
    is_deeply( $form->values, $data, 'Correct form values' );
    $data->{compound}{compound}{text_max} =~ s/\s+/ /igs;
    is_deeply( $form->field('compound')->_result,
        $data->{compound}, 'Correct field _result' );
    is( $form->result,                    undef, 'Form result is undef' );
    is( $form->field('compound')->result, undef, 'Field result is undef' );

    is(
        $form->field('compound.compound.text_max')->value,
        join( ' ', ('text') x 10 ),
        'Correct value for text_max before clearing'
    );

    $form->field('compound.compound')->clear_value();

    ok(
        !$form->field('compound.compound.text_max')->has_value,
        'text_max does not have value after parent value cleared'
    );

    done_testing();
}
