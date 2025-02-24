package MyServer;

use strict;
use warnings;
use autodie;

use Test::More;

use File::Temp;
use File::Slurper;

our $CRLF = "\x0d\x0a";
our $HEAD = join(
    $CRLF,
    'HTTP/1.0 200 OK',
    'X-test: Yay',
    'Content-type: text/plain',
    q<>, q<>,
);

our $BIGGIE = ('x' x 512);

sub new {
    my ($class) = @_;

    my $dir = File::Temp::tempdir( CLEANUP => 1 );

    my $pid = fork or do {
        $SIG{'CHLD'} = 'DEFAULT';
        MyServer::HTTP->run(
            port => 0,
            my_tempdir => $dir,
        );
    };

    my $port;

    diag "Waiting for process $pid to tell us which port it’s bound to …";

    while (!$port) {
        select( undef, undef, undef, 0.1 );

        if (-s "$dir/port") {
            $port = File::Slurper::read_text("$dir/port");
        }
    }

    diag "SERVER PORT: [$port]";

    return bless [$dir, $pid, $port], $class;
}

sub port { $_[0][2] }

sub DESTROY {
    my ($self ) = @_;

    local $SIG{'CHLD'} = 'DEFAULT';

    my $pid = $self->[1];

    diag "Destroying server (PID $pid) …";

    warn if !eval { kill 'TERM', $pid; 1 };

    waitpid $pid, 0;

    return;
}

#----------------------------------------------------------------------

package MyServer::HTTP;

use parent 'Net::Server::HTTP';

sub options {
    my $self     = shift;
    my $prop     = $self->{'server'};
    my $template = shift;

    # setup options in the parent classes
    $self->SUPER::options($template);

    $prop->{'my_tempdir'} ||= undef;
    $template->{'my_tempdir'} = \$prop->{'my_tempdir'};

    return;
}

sub post_bind_hook {
    my ($self) = @_;

    my $socket = $self->{'server'}{'sock'}[0];

    my $path = "$self->{'server'}{'my_tempdir'}/port";
    File::Slurper::write_text( $path, $socket->sockport() );

    return;
}

sub process_http_request {
    my $self = shift;

    print $MyServer::HEAD;

    my $uri_path = $ENV{'PATH_INFO'};

    print( $uri_path eq '/biggie' ? $MyServer::BIGGIE : $uri_path );
}
