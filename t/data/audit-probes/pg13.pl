our $g = 1; { no strict "refs"; ${"main::g"} = 5; } print "$g\n";
