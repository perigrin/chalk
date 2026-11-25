sub inc { $_[0]++ } our $g=1; sub t { inc(local $g); $g } print t(), "$g\n";
