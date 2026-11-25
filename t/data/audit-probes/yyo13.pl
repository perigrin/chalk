use Carp qw(confess carp); sub f { confess "deep" } sub g { f() } eval { g() }; print $@ =~ /^deep at .*\n.*main::f\(\) called at .*\n.*main::g\(\) called at/ ? "trace" : "other", "\n";
