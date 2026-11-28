my $s = "abc"; $s =~ /(a)/; sub sh { "q" =~ /(q)/; "$_[0]$1" } print sh($1), $1, "\n";
