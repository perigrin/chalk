my $s = "abc"; $s =~ /(a)/; sub sh { my $v = shift; "q" =~ /(q)/; $v } print sh($1), "\n";
