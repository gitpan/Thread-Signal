BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
} #BEGIN

BEGIN {
    warn <<EOD if -t STDERR; # only if someone is actually looking

=========================================================================
Please note that some warnings are displayed during testing.  This should
not happen, but unfortunately does.  This seems to be caused by a weird
interaction between threads, Thread::Signal and Test::More.  Should you
use Thread::Signal in a "normal" situation with warnings enabled, and you
are getting warnings, please report these.  Thank you for your attention.
=========================================================================

EOD
} #BEGIN

use Test::More tests => 11;
use strict;
use warnings;

BEGIN {use_ok( 'Thread::Signal',USR1 => 'signal' )}
can_ok( 'Thread::Signal',qw(
 automatic
 import
 othertids
 prime
 register
 registered
 signal
 tids
 unautomatic
 unregister
) );
ok( Thread::Signal->registered( 'USR1' ),	'check whether registered' );

my $running : shared = 0;
my $done : shared = 0;
my @result : shared;
my $threads = 10;

threads->new( \&thread ) foreach 1..$threads;
threads->yield until $running == $threads;

my $signalled = Thread::Signal->signal( 'USR1',-1 );
cmp_ok( $signalled,'==',$threads+1,	'check whether all signalled' );

threads->yield until $done == $threads+1;
my $worked = 
 is( join('',@result),join('',0..$threads),'check all threads processed' );

$done = 0;
@result = (''); #avoid warning for undefined value
$signalled = Thread::Signal->signal( 'USR1',-2 );
cmp_ok( $signalled,'==',$threads,	'check whether all signalled' );

threads->yield until $done == $threads;
is( join('',@result),join('',1..$threads),'check all threads processed' );

$running = 0;
$_->join foreach threads->list;

eval {Thread::Signal->signal( undef,0 )};
ok( $@ =~ m#^Must specify a signal#,	'check for invalid signal' );

eval {Thread::Signal->signal( 'ALRM',0 )};
ok( $@ =~ m#^Not allowed to send signal 'ALRM' to thread#, 'invalid signal' );

eval {Thread::Signal->signal( 'USR1',$threads+1 )};
ok( $@ =~ m#^Not allowed to send signal 'USR1' to thread#, 'invalid signal' );

ok( Thread::Signal->registered( 1,'USR1' ),	'check whether registered' );

warn <<EOD unless $worked;

*********************************************************************
*** It looks like signalling threads does NOT work on your system ***
*** 
*** This is caused by peculiarities of the operating system that  ***
***   you are using, and can unfortunately, not be fixed (yet)    ***
*********************************************************************

EOD

sub thread {
 Thread::Signal->register;
 {lock( $running ); $running++};
 1 while $running;
}

sub signal { $result[threads->tid] = threads->tid; $done++ }
