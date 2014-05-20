package Form::Data::Processor::Role::Fields;

=head1 NAME

Form::Data::Processor::Role::Fields - role for forms and fields.

=cut

use Moose::Role;
use namespace::autoclean;

use Class::Load qw(load_optional_class);
use Data::Clone ();

has fields => (
    is      => 'rw',
    isa     => 'ArrayRef[Form::Data::Processor::Field]',
    traits  => ['Array'],
    default => sub { [] },
    handles => {
        all_fields   => 'elements',
        clear_fields => 'clear',
        add_field    => 'push',
        num_fields   => 'count',
        has_fields   => 'count',
        set_field_at => 'set',
    }
);

has index => (
    is      => 'ro',
    isa     => 'HashRef[Form::Data::Processor::Field]',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        add_to_index     => 'set',
        field_from_index => 'get',
        field_in_index   => 'exists',
        clear_index      => 'clear',
    }
);

has has_fields_errors => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    trigger => sub {
        my $self = shift;

        # $_[0] - new
        # $_[1] - old

        # Tell to parent when we have errors, so parent as well
        $self->parent->has_fields_errors(1)
            if $_[0] && !$_[1] && $self->can('parent');
    }
);

has field_name_space => (
    is      => 'rw',
    isa     => 'ArrayRef[Str]',
    traits  => ['Array'],
    lazy    => 1,
    default => sub { [] },
    handles => {
        add_field_name_space => 'push',
    },
);


# Fields builder
sub _build_fields {
    my $self       = shift;
    my $field_list = [];

    # Look for fields definition in every parent role and class
    for my $sc ( reverse $self->meta->linearized_isa ) {
        my $meta = $sc->meta;

        if ( $meta->can('calculate_all_roles') ) {
            for my $role ( reverse $meta->calculate_all_roles ) {
                if ( $role->can('field_list') && $role->has_field_list ) {
                    for my $fld_def ( @{ $role->field_list } ) {
                        push @$field_list, $fld_def;
                    }
                }
            }
        }

        if ( $meta->can('field_list') && $meta->has_field_list ) {
            for my $fld_def ( @{ $meta->field_list } ) {
                push @$field_list, $fld_def;
            }
        }
    }

    $self->_process_field_array( $field_list, 0 ) if @{$field_list};
}


sub _process_field_array {
    my ( $self, $fields ) = @_;

    $fields = Data::Clone::clone($fields);

    my $num_fields   = @{$fields};
    my $num_dots     = 0;
    my $count_fields = 0;

    # Will create fields with subfields with subfields with...
    while ( $count_fields < $num_fields ) {
        for my $field ( @{$fields} ) {
            my $count = ( $field->{name} =~ tr/\.// );

            # ... but the parent field must be created first
            next unless $count == $num_dots;

            $self->_make_field($field);
            $count_fields++;
        }
        $num_dots++;
    }
}


# Field maker
sub _make_field {
    my ( $self, $field_attr ) = @_;

    my $type = $field_attr->{type} ||= 'Text';  # FDP::Field::Text by default
    my $name = $field_attr->{name};


    # +field_name means that some field attributes should be overwritten
    my $do_update;
    if ( $name =~ /^\+(.*)/ ) {
        $field_attr->{name} = $name = $1;
        $do_update = 1;
    }

    # Look class by type
    my $class = $self->_find_field_class( $type, $name );

    # Look parent for field, by default form is a parent
    my $parent = $self->_find_parent($field_attr) || $self->form;

    my $field
        = $self->_update_or_create( $parent, $field_attr, $class, $do_update );

    $parent->add_to_index( $field->name => $field ) if $parent;

    return $field;
}


# Field class finder
sub _find_field_class {
    my ( $self, $type, $name ) = @_;

    my $field_ns
        = $self->has_form
        ? $self->form->field_name_space
        : $self->field_name_space;

    my @classes;
    push @classes, $type if $type =~ s/^\+//;

    for my $ns (
        @{$field_ns},
        'Form::Data::ProcessorX::Field',
        'Form::Data::Processor::Field',
        )
    {
        push @classes, $ns . '::' . $type;
    }

    for my $class (@classes) {
        return $class if load_optional_class($class);
    }

    confess "Could not load field class '$type' for field '$name'";
}


# Field parent finder
# Return parent field (not form) or undef if there are no parent field
sub _find_parent {
    my ( $self, $field_attr ) = @_;

    my $parent;

    if ( $field_attr->{name} =~ /\./ ) {
        my @names       = split( /\./, $field_attr->{name} );
        my $simple_name = pop(@names);
        my $parent_name = join( '.', @names );

        if ( $parent = $self->field( $parent_name, undef, $self ) ) {
            confess "Parent field '$parent_name' can't contain fields for '"
                . $field_attr->{name} . "'"
                unless $parent->DOES('Form::Data::Processor::Role::Fields');

            $field_attr->{name} = $simple_name;
        }
        else {
            confess 'Could not find parent for field ' . $field_attr->{name};
        }
    }
    elsif ( !( $self->has_form && $self == $self->form ) ) {
        $parent = $self;
    }

    $field_attr->{full_name}
        = ( $parent ? $parent->full_name . '.' : '' ) . $field_attr->{name};

    return $parent;
}


sub field {
    my ( $self, $name, $f ) = @_;

    return undef unless defined $name;

    return ( $f || $self )->index->{$name}
        if exists( ( $f || $self )->index->{$name} );

    if ( $name =~ /\./ ) {
        my @names = split /\./, $name;
        $f ||= $self->form || $self;

        for my $fname (@names) {
            $f = $f->field($fname) or return;
        }

        return $f;
    }

    return;
}


sub subfield {
    my ( $self, $name ) = @_;

    return $self->field( $name, $self );
}


sub _update_or_create {
    my ( $self, $parent, $field_attr, $class, $do_update ) = @_;

    $parent ||= $self->form;
    $field_attr->{parent} = $parent;
    $field_attr->{form} = $self->form if $self->form;

    my $index = $parent->field_index( $field_attr->{name} );
    my $field;

    if ( defined $index ) {
        if ($do_update) {
            $field = $parent->field( $field_attr->{name} )
                or confess "Field to update for $field_attr->{name} not found";

            for my $key ( keys %{$field_attr} ) {
                next
                    if $key eq 'name'           # These
                    || $key eq 'form'           # field
                    || $key eq 'parent'         # attributes
                    || $key eq 'full_name'      # can not be
                    || $key eq 'type';          # changed

                $field->$key( $field_attr->{$key} ) if $field->can($key);
            }
        }
        else {
            $field = $class->new_with_traits($field_attr);
            $parent->set_field_at( $index, $field );
        }
    }
    else {
        $field = $class->new_with_traits($field_attr);
        $parent->add_field($field);
    }

    return $field;
}

sub field_index {
    my ( $self, $name ) = @_;
    my $index = 0;
    for my $field ( $self->all_fields ) {
        return $index if $field->name eq $name;
        $index++;
    }

    return;
}


sub _ready_fields {
    my $self = shift;

    for my $field ( $self->all_fields ) {
        $field->_before_ready;
        $field->ready;
    }
}


sub reset_fields {
    my $self = shift;

    for my $field ( $self->all_fields ) {
        $field->_before_reset;
        $field->reset unless $field->not_resettable;
        $field->_after_reset;

        $field->clear_value if $field->has_value;
    }
}


after clear_errors => sub {
    shift->clear_fields_errors();
};


sub clear_fields_errors {
    my $self = shift;

    return unless $self->has_fields_errors;

    $self->has_fields_errors(0);

    for my $field ( $self->all_fields ) {
        $field->clear_errors;
    }
}

sub init_input {
    my $self = shift;
    my $params = shift || {};

    confess 'Input params must be HashRef' unless ref $params eq 'HASH';

    for my $field ( $self->all_fields ) {
        my $exists = exists $params->{ $field->name };
        $field->init_input( $params->{ $field->name }, $exists );
    }
}

sub validate_fields {
    my $self = shift;

    my %values;
    for my $field ( $self->all_fields ) {
        next if $field->disabled;

        $field->validate;

        for my $code ( $field->all_external_validators ) {
            $code->($field);
        }
    }
}

around has_errors => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->has_fields_errors;
    return $self->$orig;
};

sub error_fields {
    my $self = shift;

    return ( map {$_} grep { $_->has_errors } $self->all_fields );
}

sub all_error_fields {
    my $self = shift;

    return (
        grep { $_->errors_count } map {
            (
                $_,
                $_->DOES('Form::Data::Processor::Role::Fields')
                ? $_->all_error_fields
                : ()
            );
        } $self->all_fields
    );
}

sub values {
    my $self = shift;

    return {
        map { $_->name => $_->value }
        grep { $_->has_value } $self->all_fields
    };
}

sub result {
    my $self = shift;

    return undef if $self->has_errors;

    return {
        map { $_->name => $_->_result }
        grep { $_->_has_result } $self->all_fields
    };
}

sub _find_external_validators {
    my $self  = shift;
    my $field = shift;

    my @validators;

    ( my $validator = $field->full_name ) =~ s/\./_/g;

    unless ( $self->is_form ) {
        ( my $full_name = $self->full_name ) =~ s/\./_/g;
        $validator =~ s/^\Q$full_name\E_//;
    }

    $validator = 'validate_' . $validator;

    # Search validator in current obj
    if ( my $code = $self->can($validator) ) {
        push(
            @validators,
            sub {
                my $field = shift;

                $code->( $self, $field );
            }
        );
    }

    # Search validator in parent objects
    if ( $self->can('parent') ) {
        push( @validators, $self->parent->_find_external_validators($field) );
    }

    return @validators;
}

1;
