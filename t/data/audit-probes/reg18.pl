our $g=1; sub f { $g=5; 1 } return_it(); sub return_it { my @r = ($g, f(), $g); print "@r\n" }
