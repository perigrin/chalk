sub m2 { "q" =~ /(q)/; $1 } "abc" =~ /(b)/; print $1, m2(), $1, "\n";
