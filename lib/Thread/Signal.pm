package Thread::Signal;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION : unique = '1.01';
use strict;

# Make sure we only load stuff when we actually need it

use AutoLoader 'AUTOLOAD';

# Load the XS stuff

require XSLoader;
XSLoader::load( 'Thread::Signal',$VERSION );

# Make sure we can do threads

use threads ();
use threads::shared ();

# Initialize the tid -> pid hash
# Initialize the tid -> allowed signals hash
# Thread local default list of allowed signals

our %pid : shared;    # must all be our because of AutoLoader usage
our %signal : shared;
our $default_signal;

# Satisfy -require-

1;

#---------------------------------------------------------------------------

# AutoLoader takes over from here

__END__

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N hash with signal/code ref pairs

sub register {

# Lose the class
# Set the parameter hash
# Obtain the default namespace
# Obtain the current thread id
# Create local copy of allowed signals hash, use default if first time

    shift;
    my %param = @_;
    my $namespace = caller().'::';
    my $tid = threads->tid;
    my $allowed = _allowed();

# For each signal/code pair
#  If we don't have a code reference yet
#   Prefix default namespace if none specified yet
#   Make it a true code ref
#  Set the signal
#  Mark it in the allowed hash also

    while (my($signal,$code) = each( %param )) {
        unless (ref($code)) {
            $code = $namespace.$code unless $code =~ m#::#;
            $code = \&$code;
        }
        $SIG{$signal} = $code;
        $allowed->{$signal} = undef;
    }

# Remember these settings

    _record( $allowed );
} #register

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N signal names to unregister (default: all)

sub unregister {

# Lose the class
# Set to all signals allowed if none specified

    shift;
    @_ = keys %{_allowed()} unless @_;

# For each of the signal names
#  Set the signal back to the default value
#  Removed it from the allowed hash
# Remember these settings

    foreach (@_) {
        $SIG{$_} = 'DEFAULT';
        delete( $allowed->{$_} );
    }
    _record( $allowed );
} #unregister

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2 thread id for which to check (optional, default: current)
#      3..N signals to check whether registered
# OUT: 1 whether all specified signals registered

sub registered {

# Lose the class
# Create local copy of allowed signals hash
# For each of the signal names
#  Return false if signal not in the hash
# Return true indicating all specified keys were in hash

    shift;
    my $allowed = _allowed( (@_ > 1 ? shift : '') || threads->tid );
    foreach (@_) {
        return 0 unless exists $allowed->{$_};
    }
    return 1;
} #registered

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2 signal to deliver (default: ALRM)
#      3..N thread id of thread to signal (-1 = all)
# OUT: 1 number of threads successfully signalled

sub signal {

# Lose the class
# Obtain the signal
# Die now if nothing to signal

    shift;
    my $signal = shift;
    die "Must specify a signal" unless $signal;

# Set to signal all if so indicated
# Create the not allowed list
# Die now if attempting to signal threads that are not allowed
# Send the signal to the indicated threads and return the result

    @_ = keys %pid if @_ == 1 and $_[0] == -1;
    my @notallowed = map {index( $signal{$_}," $signal " ) == -1 ? $_ : ()} @_;
    die "Not allowed to send signal '$signal' to thread(s) @notallowed"
     if @notallowed;
    kill $signal,map {$pid{$_}} @_;
} #signal

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N signals to prime

sub prime {

# Lose the class
# Set a default signal handler for all the signals specified

    shift;
    $SIG{$_} = sub {} foreach @_;
} #prime

#---------------------------------------------------------------------------

# Standard Perl features

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N hash with signal/code ref pairs

sub import { goto &register } #import

#---------------------------------------------------------------------------

# internal subroutines

#---------------------------------------------------------------------------
#  IN: 1 reference to hash with allowed keys

sub _record {

# Obtain the thread id
# Obtain the allowed signals hash
# Set the default allowed signals
# Add extra spaces for use in the allowed signals hash
# Set the pid of the thread

    my $tid = threads->tid;
    my $allowed = shift;
    $default_signal = join( ' ',keys %$allowed );
    $signal{$tid} = " $default_signal ";
    $pid{$tid} = _threadpid();
} #_record

#---------------------------------------------------------------------------
#  IN: 1 thread id (default: current, check default also)
# OUT: 1 reference to allowed hash

sub _allowed {

# Return reference to specific hash if specific hash requested
# Obtain the thread id
# Return reference to the hash

    return _hashref( $signal{shift()} ) if @_;
    my $tid = threads->tid;
    _hashref( exists($signal{$tid}) ? $signal{$tid} : $default_signal );
} #_allowed

#---------------------------------------------------------------------------
#  IN: 1 space delimited signals string
# OUT: 1 reference to hash with signals as keys

sub _hashref { my %h = map {($_,undef)} (split( ' ',shift() )); \%h } #_hashref

#---------------------------------------------------------------------------

=head1 NAME

Thread::Signal - deliver a signal to a thread

=head1 SYNOPSIS

  use Thread::Signal;  # don't activate any signal yet
  use Thread::Signal ALRM => sub { warn "Alarm went off\n" };

  Thread::Signal->register; # activate all from parent thread
  Thread::Signal->register( ALRM => sub { warn "Alarm went off\n" } );

  Thread::Signal->unregister; # dis-allow all signalling from other threads
  Thread::Signal->unregister( qw(ALRM) ); # only dis-allow specific signals

  Thread::Signal->signal( 'ALRM',$thread->tid ); # signal a single thread
  Thread::Signal->signal( 'ALRM',-1 ); # signal all threads that allow this

  print "Signal is registered\n" if Thread::Signal->registered( ,'ALRM' );

  Thread::Signal->prime( qw(ALRM USR1 USR2) ); # needed in special cases

=head1 DESCRIPTION

                  *** A note of CAUTION ***

 This module only functions on Perl versions 5.8.0 and later.
 And then only when threads are enabled with -Dusethreads.  It
 is of no use with any version of Perl before 5.8.0 or without
 threads enabled.

                  *************************

The Thread::Signal module allows you to deliver signals to any thread.
Unfortunately, this B<only> works under B<Linux> so far.

Signals are specified by their name (see B<%SIG> in L<perlvar>) and a
subroutine specification (either a name or a reference).

Threads do not inherit signals from their parents, but can be easily persuaded
to do so.

Threads can activate and de-activate the signals that they want to be
deliverable to them.  Any thread can check any other thread's deliverable
signals.

=head1 CLASS METHODS

These are the class methods.

=head2 register

 Thread::Signal->register;  # assume any signals from parent thread

 Thread::Signal->register( ALRM => sub { die "Alarm went off\n" } );

If you want a thread to be susceptible to L<signal>ling from other threads,
you B<must> register the thread with the Thread::Signal package.  You only
need to call this class method once, usually as one of the first things to do
in a thread.

All signals that the parent thread has registered, will be registered for
this thread also when you call this class method.  If you want to start a new
set of signals for this thread and all the threads created from this thread,
you must call L<unregister> first.

If you specify parameters, they should be specified as a parameter hash with
the keys being the signal names and the values being the subroutines that
should be executed when the signal is delivered.  Subroutines can be specified
as a subroutine name (assume the current namespace if none specified) or as a
code reference to an (anonymous) subroutine.

You can also register signals with C<use Thread::Signal>.

=head2 unregister

 Thread::Signal->unregister;                  # remove all

 Thread::Signal->unregister( qw(USR1 USR2) ); # remove specific only

Unregisters signals from registration with the Thread::Signal package for the
current thread.  By default, all signals that are currently registered for
this thread (or implicetely by the parent thread) will be removed.

If you specify parameters, they should be the signal names for which you wish
to remove the registration.  In that case, only the specified signals will
be unregistered.

Call L<register> with specific signal names again at a later time to allow
those signals to be delivered from other threads again.

=head2 registered

 $registered = Thread::Signal->registered( 'ALRM' ); # one signal, this thread

 $registered = Thread::Signal->registered( $tid,qw(USR1 USR2) );

The "registered" class method returns whether the current thread has registered
the indicated signal(s) with this or another thread.

If only one parameter is specified, it indicates the signal name to check for
with the registration of the current thread.

If more than one parameter is specified, then the first parameter specified
indicates the thread id to check and the other parameters indicate the signal
names that should be checked for that thread.

A true value will only be returned if B<all> specified signal names are
registered with the indicated thread.  In all other cases, a false value will
be returned.

=head2 signal

 Thread::Signal->signal( 'ALRM',-1 );   # signal all registered threads

 Thread::Signal->signal( 'ALRM',@tid ); # deliver signal to specific threads

The "signal" class method acts exactly the same as the kill() function,
except you B<must> specify thread id's instead of process id's.

The special value B<-1> specifies that all L<register>ed threads should be
signalled.

=head2 prime

 Thread::Signal->prime( qw(ALRM USR2) ); # circumvent bug in 5.8.0

Because of a bug/feature in Perl 5.8.0, a signal (in the %SIG hash) B<must>
be assigned in a thread if any of the threads that are created by that thread,
want to reliably use that signal.

In most cases you don't have to worry about this.  However, if you do have
a situation in which you do not want a signal to be deliverable to the parent
thread, but you B<do> want to have those signals deliverable by the child
threads, you basically have two options.

=over 2

=item use Thread::Signal->prime

By calling Thread::Signal->prime with the signal names that you want to be
deliverable in chile threads.

=item register, then unregister

You can also first L<register> all of the signals with the appropriate handling
routines, start the child threads in which you want the signals to be
deliverable, and then call L<unregister> without parameters to have the signals
unregistered for the current thread.

=head1 OPTIMIZATIONS

This module uses L<AutoLoader> to reduce memory and CPU usage. This causes
subroutines only to be compiled in a thread when they are actually needed at
the expense of more CPU when they need to be compiled.  Simple benchmarks
however revealed that the overhead of the compiling single routines is not
much more (and sometimes a lot less) than the overhead of cloning a Perl
interpreter with a lot of subroutines pre-loaded.

=head1 CAVEATS

Due to a bug in the implementation of B<CLONE> in Perl 5.8.0, it is impossible
to make the registration process automatic.  Which may be a bonus.

Because of a bug with signalling in Perl 5.8.0, an entry in the %SIG hash
B<must> have been assigned in a thread before it can be used in any of the
threads started from that thread.  The L<prime> class method gives you an easy
way to do that.

=head1 AUTHOR

Elizabeth Mattijsen, <liz@dijkmat.nl>.

Please report bugs to <perlbugs@dijkmat.nl>.

=head1 COPYRIGHT

Copyright (c) 2002 Elizabeth Mattijsen <liz@dijkmat.nl>. All rights
reserved.  This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<AutoLoader>.

=cut
