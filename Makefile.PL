require 5.008;
use threads (); # just to force breakage if threads are not available
use ExtUtils::MakeMaker;
eval "use Devel::Required";

WriteMakefile (
 NAME		=> "Thread::Signal",
 AUTHOR		=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
 ABSTRACT	=> 'deliver a signal to a thread',
 VERSION_FROM	=> 'lib/Thread/Signal.pm',
 PREREQ_PM	=> {
		    load => 0,
                   },
);
