use Text::ParseWords; print join("|", shellwords(q{a 'b c' "d e" f\ g})), " ", join("|", quotewords(",", 0, q{x,"y,z",w})), "\n";
