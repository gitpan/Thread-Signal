package Thread::Signal;

# Make sure we have version info for this module
# Make sure we do everything by the book from now on

our $VERSION = '1.03';
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
# Initialize hash with automatically registered signals

our %pid : shared;    # must all be our because of AutoLoader usage
our %signal : shared;
our %automatic;

# Initialize thread local parent thread id
# Initialize thread local thread id
# Save the pid of the current base thread
# Save "original" thread creation routine reference

our $ptid;
our $tid = threads->tid;
$pid{$tid} = _threadpid();
my $new = \&threads::new;

# Allow for dirty tricks
# Hijack the thread creation routine with a sub that
#  Saves the class
#  Save the original reference of sub to execute
#  Creates a new thread with a sub that
#   Set the parent thread id
#   Save the current thread id (for easier access and setting parent later)
#   Sets the pid for the current thread
#   Mark the automatic signals as allowed for this thread
#   And starts execute the original sub with the right parameters

{no strict 'refs';
 *threads::new = sub {
     my $class = shift;
     my $sub = shift;
     $new->( $class,sub {
         $ptid = $tid;
         $tid = threads->tid;
         $pid{$tid} = _threadpid();
         $signal{$tid} = join( ' ','',keys %automatic,'' );
         goto &$sub;
     },@_ );
 };
} #no strict 'refs'

# Satisfy -require-

1;

#---------------------------------------------------------------------------

# AutoLoader takes over from here

__END__

#---------------------------------------------------------------------------

# class methods

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N hash with signal/code ref pairs (default: parent threads)

sub register {

# Lose the class
# Create hash with allowed signals here

    shift;
    my $allowed = _allowed();
    
# If we're to register specific signals
#  Set the parameter hash
#  Obtain the default namespace
#  For each signal/code pair

    if (@_) {
        my %param = @_;
        my $namespace = caller().'::';
        while (my($signal,$code) = each( %param )) {

#   If we don't have a code reference yet
#    Prefix default namespace if none specified yet
#    Make it a true code ref
#   Set the signal
#   Mark it in the allowed hash also
#  Remember these settings for this thread

            unless (ref($code)) {
                $code = $namespace.$code unless $code =~ m#::#;
                $code = \&$code;
            }
            $SIG{$signal} = $code;
            $allowed->{$signal} = undef;
        }
	_record( $allowed );

# Else (just activating the signals of the parent thread)
#  Make sure the default signals are known

    } else {
        $signal{$tid} = $signal{$ptid};
    }
} #register

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N signal names to unregister (default: all)

sub unregister {

# Lose the class
# Set to all signals allowed if none specified

    shift;
    my $allowed = _allowed();
    @_ = keys %$allowed unless @_;

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
#      2..N signals that should be registered automatically
# OUT: 1..N current signals that should be registered automatically

sub automatic {

# Obtain the class
# Set all new automatically registered signals specified
# Return the current set

    my $class = shift;
    $automatic{$_} = undef foreach @_;
    keys %automatic;
} #automatic

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2..N signals that should be _not_ auto-registered (default: all)
# OUT: 1..N current signals that will be registered automatically

sub unautomatic {

# Obtain the class
# If specific signal names specified
#  Remove specified automatically registered signals
# Else (want to remove all)
#  Just reset the hash
# Return the current set

    my $class = shift;
    if (@_) {
        delete( $automatic{$_} ) foreach @_;
    } else {
        %automatic = ();
    }
    keys %automatic;
} #unautomatic

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
    my $allowed = _allowed( (@_ > 1 ? shift : '') || $tid );
    foreach (@_) {
        return 0 unless exists $allowed->{$_};
    }
    return 1;
} #registered

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2 signal to deliver (default: ALRM)
#      3..N thread id of thread to signal (-1 = all, -2 = all but current)
# OUT: 1 number of threads successfully signalled

sub signal {

# Lose the class
# Obtain the signal
# Die now if nothing to signal

    shift;
    my $signal = shift;
    die "Must specify a signal" unless $signal;

# If we're to signal all threads that allow this signal
#  Find out which threads that are and send the signal to them, return result

    if (@_ == 1 and $_[0] < 0) {
        kill $signal,
         _tids2pids( $_[0] == -1 ? tids( 0,$signal ) : othertids( 0,$signal ) );

# Else (only specific threads)
#  Create the not allowed list
#  Die now if attempting to signal threads that are not allowed
#  Send the signal to the indicated threads and return the result

    } else {
        my @notallowed = sort {$a <=> $b}
         map {index( $signal{$_}," $signal " ) == -1 ? $_ : ()} @_;
        die "Not allowed to send signal '$signal' to thread(s) @notallowed"
         if @notallowed;
        kill $signal,map {$pid{$_}} @_;
    }
} #signal

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2 signal
#      3 flag: check existence of threads
# OUT: 1..N thread ID's that have this signal enabled

sub tids {

# Create searchable version of signal
# Create list of tids which have the signal
# Map this list to ones that have an active pid associated to it, drop inactives
# Return what we found

    my $signal = " $_[1] ";
    my @tid = map {index( $signal{$_},$signal ) != -1 ? $_ : ()} keys %pid;
    @tid = map {kill 0,$pid{$_} ? $_ : delete( $pid{$_} ),()} @tid if $_[2];
    @tid;
} #tids

#---------------------------------------------------------------------------
#  IN: 1 class (ignored)
#      2 signal
#      3 flag: check existence of threads
# OUT: 1..N thread ID's other than current, that have this signal enabled

sub othertids { map {$_ != $tid ? $_ : ()} tids( @_ ) } #othertids

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

sub _record { $signal{$tid} = join( ' ','',keys %{shift()},'' ) } #_record

#---------------------------------------------------------------------------
#  IN: 1 thread id (default: current)
# OUT: 1 reference to allowed hash

sub _allowed {

# Create hash of what we have saved in the shared signal hash
# Return a reference to it

    my %hash = map {($_,undef)} split( ' ',$signal{shift() || $tid} );
    \%h;
} #_allowed

#---------------------------------------------------------------------------
#  IN: 1..N thread ID's to convert
# OUT: 1..N process ID's

sub _tids2pids { map {$pid{$_} ? $pid{$_} : ()} @_ } #_tids2pids

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

  Thread::Signal->automatic( 'USR1' );   # auto-register in new threads
  Thread::Signal->unautomatic;           # don't auto-register any
  Thread::Signal->unautomatic( 'USR1' ); # don't auto-register specific

  Thread::Signal->signal( 'ALRM',$thread->tid ); # signal a single thread
  Thread::Signal->signal( 'ALRM',-1 ); # signal all threads that allow this

  $registered = Thread::Signal->registered( 'ALRM' ); # check own thread
  $registered = Thread::Signal->registered( $tid,qw(ALRM USR2) ); # other thread

  @tid = Thread::Signal->tids( 'ALRM' );       # threads with 'ALRM'
  @tid = Thread::Signal->othertids( 'ALRM' );  # threads except this with 'ALRM'

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

Threads do not inherit signals from their parents by default, but can be
easily persuaded to do so either automatically or on a thread-by-thread
basis.

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

=head2 automatic

 Thread::Signal->automatic( qw(ALRM USR1) );

 @automatic = Thread::Signal->automatic;

The "automatic" class method sets and returns the B<names> of the signals that
will be automatically L<register>ed when a new thread is started.  Please note
that signals B<must> have been L<register>ed at least once by any of the parent
threads for the signals to actually be active inside the new threads.

Call method L<unautomatic> to remove signals from being automatically
registered in newly created threads.

=head2 unautomatic

 Thread::Signal->unautomatic; # no signal will be registered automatically

 Thread::Signal->unautomatic( qw(ALRM USR1) );

 @automatic = Thread::Signal->unautomatic;

The "unautomatic" class method removes the B<names> of the signals that
will be automatically L<register>ed when a new thread is started.  Calling
this method for a signal only makes sense if method L<automatic> was called
earlier for the same signal.  All signals that will be automatically
registered, will be removed if this method is called without parameters.

All signals that are automatically registered are returned.

Call method L<automatic> to add signal names for automatic registration
again.

=head2 signal

 Thread::Signal->signal( 'ALRM',-1 );   # signal all registered threads

 Thread::Signal->signal( 'ALRM',@tid ); # deliver signal to specific threads

The "signal" class method acts exactly the same as the kill() function,
except you B<must> specify thread id's instead of process id's.

The special value B<-1> specifies that all L<register>ed threads should be
signalled.  The special value B<-2> specifies that all registered threads
B<except> the current thread should be signalled.

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

=head2 tids

 @tid = Thread::Signal->tids( 'ALRM' );   # just return thread ID's

 @tid = Thread::Signal->tids( 'ALRM',1 ); # also check whether still valid

The "tids" class method returns the thread ID's of the threads that have
registered the specified signal.  The second input parameter can be used to
indicate that a check should be made whether all of these threads are
actually still active.  Check L<othertids> for obtaining all threads that
have a signal registered B<except> the current thread.

=head2 othertids

 @tid = Thread::Signal->othertids( 'ALRM' );   # just return thread ID's

 @tid = Thread::Signal->othertids( 'ALRM',1 ); # also check whether still valid

The "othertids" class method returns the thread ID's of the threads that have
registered the specified signal B<without including the ID of the current
thread>.  The second input parameter can be used to indicate that a check
should be made whether all of these threads are actually still active.
Check L<tids> for obtaining all threads that have a signal registered
B<including> the current thread.

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
deliverable in child threads.

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

This module only runs on systems that use a (pseudo) process for each thread.
To my knowledge, this happens only on Linux systems.  I'd be interested in
knowing about other OS's on which this implementation also works, so that I
can add these to the documentation.

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
