our $g=1; my @r=eval { local $g=2; ($g,$g) }; print "@r $g\n";
