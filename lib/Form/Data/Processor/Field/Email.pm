package Form::Data::Processor::Field::Email;

# ABSTRACT: email field

use Form::Data::Processor::Moose;
use namespace::autoclean;

extends 'Form::Data::Processor::Field';

use Email::Valid;


has email_valid_params => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
);

has reason => (
    is       => 'ro',
    isa      => 'Str',
    init_arg => undef,
    writer   => '_set_reason',
    clearer  => '_clear_reason',
);

has _result => (
    is       => 'rw',
    isa      => 'Str',
    init_arg => undef,
    writer   => '_set_result',
    clearer  => '_clear_result',
);


sub BUILD {
    my $self = shift;

    $self->set_error_message(
        email_invalid => 'Field value is not a valid email' );
}

before reset => sub {
    $_[0]->_clear_reason;
    $_[0]->_clear_result;
};


sub internal_validation {
    my $self = shift;

    return if $self->has_errors || !$self->has_value || !defined $self->value;

    return $self->add_error('email_invalid')
        unless $self->validate_email( $self->value );
};

sub validate_email {
    my ( $self, $value ) = @_;

    local $Email::Valid::Details;

    my $checked = Email::Valid->address(
        %{ $self->email_valid_params },         #
        -address => $value,                     #
    );

    return $self->_set_result($checked) if $checked;

    $self->_set_reason($Email::Valid::Details);

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 SYNOPSIS

    package My::Form;

    use Form::Data::Processor::Moose;
    extends 'Form::Data::Processor::Form';

    has_field email => ( type => 'Email', email_valid_params => { -tldcheck => 1 } );


=head1 DESCRIPTION

This field validates email via L<Email::Valid>.

This field is directly inherited from L<Form::Data::Processor::Field>.

Field sets own error messages:

    email_invalid => 'Field value is not a valid email'


=attr email_valid_params

=over 4

=item Type: HashRef

=item Default: {}

=back

Validate parameters for Email::Valid could be provided via this attribute.


=method reason

=over 4

=item Return: Str | undef

=back

On success validation returns C<undef>. When validation is failed, this method
returns L<Email::Valid/details> about actual error.


=method validate_email

=over 4

=item Arguments: $value

=item Return: bool

=back

Check if value is valid email address.

=cut
