my $s = "abc"; $s =~ /(a)/; sub sh { my ($v) = @_; "q" =~ /(q)/; $v . $1 } print sh($1), $1, "\n";
