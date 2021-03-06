use strict;
use warnings;

use utf8;

use Test::More;
use Test::Exception;
use Test::Memory::Cycle;

use FindBin;
use lib ( "$FindBin::Bin/lib", "$FindBin::Bin/../lib" );

use Data::Dumper;
use Time::HiRes qw(gettimeofday tv_interval);

use Moose::Util::TypeConstraints;

package Form::Field::Contains {
    use Form::Data::Processor::Moose;
    extends 'Form::Data::Processor::Field::Compound';

    has_field text_req => ( type => 'Text', required => 1 );
    has_field text     => ( type => 'Text', required => 0 );
}

package Form::Field::Repeatable1 {
    use Form::Data::Processor::Moose;
    extends 'Form::Data::Processor::Field::Repeatable';

    has_field text => ( type => 'Text', required => 1, );
}

package Form::Field::Repeatable4 {
    use Form::Data::Processor::Moose;
    extends 'Form::Data::Processor::Field::Repeatable';

    has_field 'contains' => ( type => '+Form::Field::Contains' );
}


package Form {
    use Form::Data::Processor::Moose;

    extends 'Form::Data::Processor::Form';

    # So data looks like
    # {
    #   rep_1 => [
    #       {
    #           text => 'Text'
    #       },
    #       ...
    #   ],
    #   rep_2 => [
    #       {
    #           text_min => 'Text',
    #       },
    #       ...
    #   ],
    #   rep_3 => [
    #       {
    #           rep => [
    #               {
    #                   text => 'Text',
    #               },
    #               ...
    #           ],
    #           text_min => 'Text',
    #       },
    #       ...
    #   ],
    #   rep_4 => [
    #       {
    #           text_req => 'Required',
    #       },
    #       {
    #           text_req => 'Required',
    #           text     => 'Text',
    #       },
    #       ...
    #   ],
    #   rep_5 => [ 'Text', ... ],
    # }

#<<<
    has_field 'rep_1' => (
        type             => '+Form::Field::Repeatable1',
        max_input_length => 10,
    );

    has_field 'rep_2' => (
        type => 'Repeatable',
        apply  => [
            {
                input_transform => sub {
                    my ( $value, $self ) = @_;
                    return $value unless $value;

                    if ( ( $value->[0]{text_min} || '' )
                        =~ /^_input_transform=(\d+)$/ )
                    {
                        $value->[0]{text_min} = 'X' x $1;
                    }
                    return $value;
                },
            },
        ],
    );

    has_field 'rep_2.contains'           => ( type => 'Compound', );
    has_field 'rep_2.contains.text_min'  => ( type => 'Text', minlength => 10, );

    has_field 'rep_3'                    => ( type => 'Repeatable' );
    has_field 'rep_3.rep'                => ( type => 'Repeatable' );
    has_field 'rep_3.rep.text'           => ( type => 'Text' );
    has_field 'rep_3.text_min'           => ( type => 'Text', minlength => 10, );

    has_field 'rep_4'                    => ( type => '+Form::Field::Repeatable4' );

    has_field 'rep_5'                    => ( type => 'Repeatable', disabled => 1, );
    has_field 'rep_5.contains'           => ( type => 'Text' );

#>>>

    sub dump_errors {
        return { map { $_->full_name => [ $_->all_errors ] }
                shift->all_error_fields };
    }

    sub validate_rep_3_contains_rep_contains_text {
        my $self  = shift;
        my $field = shift;

        return if $field->has_errors;

        $field->add_error('validate_rep_3_contains_rep_contains_text')
            if ( $field->value || '' ) =~ /try/;
    }

    sub validate_rep_4_contains_text_req {
        my $self  = shift;
        my $field = shift;

        return if $field->has_errors;

        $field->add_error('validate_rep_4_text_req')
            if ( $field->value || '' ) =~ /try/;
    }
}

package main {
    my $form = Form->new();
    memory_cycle_ok( $form, 'No memory cycles on ->new' );

    my $data = {
        rep_1 => [
            (
                {
                    text => 'Text'
                }
            ) x 10
        ],
        rep_2 => [
            (
                {
                    text_min => 'Text' x 3,
                }
            ) x 32
        ],
        rep_3 => [
            (
                {
                    rep => [
                        (
                            {
                                text => 'Text',
                            }
                        ) x 32
                    ],
                    text_min => 'Text' x 3,
                }
            ) x 32
        ],
        rep_4 => [
            (
                {
                    text_req => 'Required',
                },
                {
                    text_req => 'Required',
                    text     => 'Text',
                }
            ) x 32
        ],
    };

    for ( 1 .. ( $ENV{DO_BENCH} ? 10 : 1 ) ) {
        my $t0 = [gettimeofday];
        $form->process($data);
        diag tv_interval( $t0, [gettimeofday] );
    }

    subtest 'FDP::Field::clone' => sub {
        ok(
            $form->field('rep_3.0.rep.0.text')
                ->isa('Form::Data::Processor::Field::Text'),
            'Cloned subfield for repeatable found'
        );

        is( $form->field('rep_1.0')->full_name,
            'rep_1.0', 'First subfield for rep_1 found' );

        is( $form->field('rep_1.9')->full_name,
            'rep_1.9', 'Last subfield for rep_1 found' );

        ok( !$form->field('rep_1.11'),
            'Subfield rep_1.10 not found for rep_1' );

        $form->field('rep_1.9')->disabled(1);
        $form->field('rep_1')->init_input( [ (undef) x 10 ], 1 );
        $form->reset_fields;
        is( $form->field('rep_1.9')->disabled,
            0, 'Subfield is reset after clear form' );

        $form->process( { rep_1 => [ ( {} ) x 3 ] } );
        is_deeply(
            $form->dump_errors,
            { map { +"rep_1.$_.text" => ['Field is required'] } ( 0 .. 2 ) },
            'Subfield names are fine for errors'
        );

    };


    subtest 'FDP::Repeatable::max_input_length' => sub {
        ok( $form->field('rep_1')->has_fields, 'rep_1 has fields' );
        $form->field('rep_1')->clear_fields;
        ok( !$form->field('rep_1')->has_fields, 'rep_1 does not have fields' );
        $form->field('rep_1')->set_default_value( max_input_length => 128 );

        ok( $form->process( { rep_1 => [ ( { text => 'str' } ) x 128 ] } ),
            'Form validated without errors' );

        $form->field('rep_1')->set_default_value( max_input_length => 10 );

        $form->process( { rep_1 => [ (undef) x 11 ] } );
        is_deeply(
            $form->dump_errors,
            { "rep_1" => ['Input exceeds max length'] },
            'Input exceeds max length error message'
        );
    };

    $form->process( { rep_1 => [ ( { text => 'Text' } ) x 5 ] } );
    $form->process( { rep_1 => [ ( { text => 'Text' } ) x 2 ] } );

    is_deeply(
        $form->result->{rep_1},
        [ { text => 'Text' }, { text => 'Text' }, ],
        'Only two fields returned'
    );


    subtest 'external_validators' => sub {
        my $data = {
            rep_1 => [
                {
                    text => 'Text'
                }
            ],
            rep_2 => [
                {
                    text_min => 'Text' x 10,
                }
            ],
            rep_3 => [
                {
                    rep => [
                        {
                            text => 'Text',
                        },
                        {
                            text => 'try',
                        }
                    ],
                    text_min => 'Text' x 10,
                }
            ],
            rep_4 => [
                {
                    text_req => 'Required',
                },
                {
                    text_req => 'try',
                    text     => 'Text',
                }
            ],
        };
        ok( !$form->process($data), 'Form validated with errors' );

        is_deeply(
            $form->dump_errors,
            {
                'rep_3.0.rep.1.text' =>
                    ['validate_rep_3_contains_rep_contains_text'],
                'rep_4.1.text_req' => ['validate_rep_4_text_req'],
            },
            'OK, right error messages'
        );
    };

    subtest 'input_transform' => sub {
        my $data = {
            rep_2 => [
                {
                    text_min => '_input_transform=5',
                }
            ]
        };
        ok( !$form->process($data), 'Form validated with errors' );
        is_deeply(
            $form->dump_errors,
            {
                'rep_2.0.text_min' => ['Field is too short'],
            },
            'Correct error messages'
        );

        $data = {
            rep_2 => [
                {
                    text_min => '_input_transform=15',
                }
            ]
        };
        ok( $form->process($data), 'Form validated with errors' );
        is( $form->field('rep_2.0.text_min')->result,
            'X' x 15, 'Result for field is correct' );
    };

    subtest 'clear_empty' => sub {
        my $f = $form->field('rep_3');

        $f->init_input( undef, 1 );
        ok( $f->has_value, 'OK, field has value on empty input' );

        is( $f->clear_empty(1), 1,
            'Now field shoudnt have value on undef input' );

        $f->init_input( undef, 1 );
        ok( !$f->has_value, 'OK, field doesnt have value on undef input' );

        $f->init_input( [] );
        ok( !$f->has_value, 'OK, field doesnt have value on empty input' );

        $f->init_input( [ undef, undef, undef, undef ] );
        ok( !$f->has_value,
            'OK, field doesnt have value on [undef, undef, ...] input' );

        $f->clear_empty(0);
    };

    subtest 'plain text' => sub {
        my $f = $form->field('rep_5');
        $f->disabled(0);

        $f->init_input( [ 'Text 1', ' Text 2 ', ' Text 3' ], 1 );
        $f->validate();
        ok( !$f->has_errors, 'field validated' );
        is_deeply(
            $f->result,
            [ 'Text 1', 'Text 2', 'Text 3', ],
            'field result OK'
        );
    };

    subtest 'undef' => sub {
        my $f = $form->field('rep_5');
        $f->disabled(0);

        $f->init_input( undef, 1 );
        $f->validate();
        ok( !$f->has_errors, 'field validated' );
        is_deeply( $f->result, undef, 'field result OK' );
    };

    subtest 'required' => sub {
        $form->field('rep_1')->contains->field('text')->disabled(1);
        $form->field('rep_1')->set_default_value( fallback => 1 );

        ok(
            $form->process(
                {
                    rep_1 => [ { text => [] } ]
                }
            ),
            'Form validated without errors on fallback(1)'
        );

        $form->field('rep_1')->set_default_value( fallback => 0 );
        $form->field('rep_1')->contains->field('text')->disabled(0);
        ok(
            !$form->process(
                {
                    rep_1 => [ { text => [] } ]
                }
            ),
            'Form validated with errors on fallback(0)'
        );


        $form->field('rep_1')->set_default_value( fallback => 0 );

        $form->field('rep_1')->set_default_value( required => 1 );
        $form->field('rep_3')->set_default_value( required => 1 );
        $form->field('rep_4')->set_default_value( required => 1 );
        $form->field('rep_5')
            ->set_default_value( required => 1, disabled => 0 );

        my $data = {
            rep_1 => [],
            rep_3 => [],
            rep_4 => undef,
        };
        ok( !$form->process($data), 'Form validated with errors' );

        is_deeply(
            $form->dump_errors,
            {
                'rep_1' => ['Field is required'],
                'rep_3' => ['Field is required'],
                'rep_4' => ['Field is required'],
                'rep_5' => ['Field is required'],
            },
            'OK, right error messages'
        );
    };


    subtest "reset CAVEATS" => sub {
        subtest 'after setup_form' => sub {
            $form->field('rep_1')->clear_fields;

            # 1
            $form->process( { rep_1 => [ ( { text => 'Text' } ) x 5 ] } );

            # 2 Emulate process with less repeatable count
            $form->clear_form;

            $form->setup_form({ rep_1 => [ ( { text => 'Text' } ) x 3 ] });
            $_->field('text')->disabled(1) for $form->field('rep_1')->all_fields;

            $form->init_input( $form->params );
            $form->validate_fields;

            # 3 Process with more repeatable count than on #2
            $form->process( { rep_1 => [ ( { text => 'Text' } ) x 5 ] } );

            ok( ! $form->field("rep_1.$_.text")->disabled, "#$_ is not disabled" ) for (0, 1, 2);
            ok(   $form->field("rep_1.$_.text")->disabled, "#$_ is disabled" )     for (3, 4);
        };

        subtest 'after init_input' => sub {
            $form->field('rep_1')->clear_fields;

            # 1
            $form->process( { rep_1 => [ ( { text => 'Text' } ) x 5 ] } );

            # 2 Emulate process with less repeatable count
            $form->clear_form;

            $form->setup_form({ rep_1 => [ ( { text => 'Text' } ) x 3 ] });
            $form->field('rep_1')->contains->field('text')->disabled(1);

            $form->init_input( $form->params );
            $_->field('text')->disabled(1) for $form->field('rep_1')->all_fields;

            $form->validate_fields;

            # 3 Emulate process with more repeatable count than on #1
            $form->clear_form;

            $form->setup_form({ rep_1 => [ ( { text => 'Text' } ) x 6 ] });
            $form->field('rep_1')->contains->field('text')->disabled(0);

            $form->init_input( $form->params );
            $form->validate_fields;

            ok( ! $form->field("rep_1.$_.text")->disabled, "#$_ is not disabled" ) for ( 0 .. 5 );
        };
    };

    memory_cycle_ok( $form, 'Still no memory cycles' );
    done_testing();
}
