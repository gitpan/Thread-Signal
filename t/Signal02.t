BEGIN {				# Magic Perl CORE pragma
    if ($ENV{PERL_CORE}) {
        chdir 't' if -d 't';
        @INC = '../lib';
    }
}

use Test::More tests => 5;
use strict;

BEGIN {use_ok( 'Thread::Signal' )}
Thread::Signal->register( 'USR1',\&signal );
ok( Thread::Signal->registered( 'USR1' ),	'check whether registered' );
cmp_ok( scalar(Thread::Signal->automatic('USR1')),'==',1,'check whether automatic' );

my $running : shared = 0;
my $done : shared = 0;
my @result : shared;
my $threads = 10;

threads->new( \&thread ) foreach 1..$threads;
threads->yield until $running == $threads;

my $signalled = Thread::Signal->signal( 'USR1',0..$threads );
cmp_ok( $signalled,'==',$threads+1,	'check whether all signalled' );

threads->yield until $done == $threads+1;
is( join(' ',@result),join(' ',0..$threads),'check all threads processed' );

$running = 0;
$_->join foreach threads->list;

sub thread {
 {lock( $running ); $running++};
 1 while $running;
}

sub signal { $result[threads->tid] = threads->tid; $done++ }
