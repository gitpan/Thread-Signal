require 5.008;
use threads (); # just to force breakage if threads are not available
use ExtUtils::MakeMaker;

WriteMakefile (
 NAME		=> "Thread::Signal",
 ($[ >= 5.005) ?
 (AUTHOR	=> 'Elizabeth Mattijsen (liz@dijkmat.nl)',
  ABSTRACT	=> 'deliver a signal to a thread') : (),
 VERSION_FROM	=> 'lib/Thread/Signal.pm',
 PREREQ_PM	=> {
		    load => 0,
                   },
);
