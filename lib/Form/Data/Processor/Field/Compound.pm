package Form::Data::Processor::Field::Compound;

# ABSTRACT: field with subfields

use Form::Data::Processor::Moose;
use namespace::autoclean;

extends 'Form::Data::Processor::Field';

with 'Form::Data::Processor::Role::Fields';

sub BUILD {
    my $self = shift;

    $self->_build_fields;
}

after _init_external_validators => sub {
    my $self = shift;

    $_->_init_external_validators for $self->all_fields;
};

before ready => sub { $_[0]->_ready_fields };

before reset => sub {
    my $self = shift;

    return if $self->not_resettable;

    $self->reset_fields;
};

before clear_value => sub {
    my $self = shift;

    # Clear values for subfields
    for my $field ( $self->all_fields ) {
        $field->clear_value if $field->has_value;
    }
};


sub init_input {
    my $self = shift;

    my $value = $self->_init_input(@_);

    return unless ref $value eq 'HASH';

    # init_input for all subfields
    for my $subfield ( $self->all_fields ) {
        my $subfield_name = $subfield->name;

        $subfield->init_input( $value->{$subfield_name},
            exists( $value->{$subfield_name} ) );
    }

    return $self->set_value(
        {
            map { $_->name => $_->value }
            grep { $_->has_value } $self->all_fields
        }
    );
}


around is_empty => sub {
    my $orig = shift;
    my $self = shift;

    return 1 if $self->$orig(@_);

    # OK, there is some input, so we have value
    my $value = @_ ? $_[0] : $self->value;

    return 0 unless ref $value eq 'HASH';

    # Seems it is HashRef. Value is not empty if Hash contains keys
    return !( keys %{$value} );
};


sub internal_validation {
    my $self = shift;

    return if $self->has_errors || !$self->has_value || !defined $self->value;

    return $self->add_error( 'invalid', $self->value )
        if ref $self->value ne 'HASH';

    # Validate subfields
    $self->validate_fields;
}


sub _result {
    return {
        map { $_->name => $_->result }
        grep { $_->has_result } shift->all_fields
    };
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

    ...
    # In form definition
    has_field 'address'               => (type => 'Compound');
    has_field 'address.country'       => (type => 'Text', required => 1);
    has_field 'address.state'         => (type => 'Text');
    has_field 'address.city'          => (type => 'Text', required => 1);
    has_field 'address.address1'      => (type => 'Text', required => 1);
    has_field 'address.address2'      => (type => 'Text');
    has_field 'address.zip'           => (type => 'Text', required => 1);
    has_field 'address.phones'        => (type => 'Compound');
    has_field 'address.phones.home'   => (type => 'Text');
    has_field 'address.phones.mobile' => (type => 'Text');

    ...

    # In your code
    $form->process(
        params => {
            address => {
                country  => 'RUSSIAN FEDERATION',
                state    => 'Vladimirskaya obl.',
                city     => 'Vladimir',
                address1 => 'Gorkogo ul., 6',
                zip      => '600008',
            }
        }
    );

=head1 DESCRIPTION

This field validates compound data (HASH), where keys are subfields,
and their values are values for correspond subfield.

This field is directly inherited from L<Form::Data::Processor::Field>
and does L<Form::Data::Processor::Role::Fields>.

When input value is not HashRef, then it raises error C<invalid>.

=cut
