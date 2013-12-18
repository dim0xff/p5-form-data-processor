package Form::Data::Processor::Role::Errors;

use Moose::Role;
use namespace::autoclean;

use List::MoreUtils qw(uniq);

has errors => (
    is      => 'rw',
    isa     => 'ArrayRef[Str]',
    traits  => ['Array'],
    default => sub { [] },
    handles => {
        _all_errors  => 'elements',
        clear_errors => 'clear',
        _add_error   => 'push',
        has_errors   => 'count',
        errors_count => 'count',
    }
);

has error_messages => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    builder => '_build_error_messages',
    handles => {
        set_error_message => 'set',
        get_error_message => 'get',
    },
);

sub _build_error_messages { {} }

sub all_errors {
    return uniq( shift->_all_errors );
}

sub add_error {
    my $self  = shift;
    my $error = shift;

    $self->parent->has_fields_errors(1) if $self->can('parent');
    return $self->_add_error( $self->get_error_message($error) || $error );
}

1;
