package Form::Data::Processor::Field::Boolean;

# ABSTRACT: boolean field

use Form::Data::Processor::Moose;
use namespace::autoclean;

extends 'Form::Data::Processor::Field';

has force_result => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);


after populate_defaults => sub {
    my $self = shift;

    $self->set_default_value( force_result => $self->force_result, );
};


around validate_required => sub {
    my $orig = shift;
    my $self = shift;

    return 0 unless $self->$orig();
    return 0 unless $self->value;

    return 1;
};


sub has_result {
    my $self = shift;

    return 0 if $self->disabled;
    return 1 if $self->force_result;

    return $self->has_value;
}

sub result {
    my $self = shift;

    return undef if $self->has_errors;

    return $self->_result;
}

sub _result { return ( shift->value ? 1 : 0 ) }


__PACKAGE__->meta->make_immutable;


1;

__END__

=head1 SYNOPSIS

    package My::Form::Search;
    use Form::Data::Processor::Moose;
    extends 'Form::Data::Processor::Form';

    has_field agree_license     => ( type => 'Boolean', required     => 1 );
    has_field search_with_photo => ( type => 'Boolean', force_result => 1 );

    # Addition fields for search
    ...


=head1 DESCRIPTION

This field represent boolean data.

This field is directly inherited from L<Form::Data::Processor::Field>.

B<Notice:> all current attributes are resettable.


=attr force_result

=over 4

=item Type: Bool

=item Default: false

=back

If C<true>, then field has result when input value is not provided, and result
is C<0>. Otherwise there is no result for this field, when input value is not
provided.


=attr required

Field value should not be empty (C<undef>, C<0>, C<''> etc.). Also see
L<Form::Data::Processor::Field/required>.

=cut
