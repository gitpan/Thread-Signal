BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use Test::More tests => 11;
use strict;

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
is( join('',@result),join('',0..$threads),'check all threads processed' );

$done = 0;
@result = ();
my $signalled = Thread::Signal->signal( 'USR1',-2 );
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

sub thread {
 Thread::Signal->register;
 {lock( $running ); $running++};
 1 while $running;
}

sub signal { $result[threads->tid] = threads->tid; $done++ }
