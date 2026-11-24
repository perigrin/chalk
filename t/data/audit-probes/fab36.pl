package C; sub hi { "hi" } package main; my $m=C->can("hi"); print $m->("C"), C->can("no") ? 1 : 0, "\n";
