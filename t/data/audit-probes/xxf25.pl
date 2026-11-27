our ($g,$h) = (1,2); { local $g = 5; local $h = $g + 1; { local $g = $h + 1; print "$g$h" } print "$g$h" } print "$g$h\n";
