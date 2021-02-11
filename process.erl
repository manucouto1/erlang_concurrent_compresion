-module(process).

-export([comp_proc_loop/3, decomp_proc_loop/3]).


comp_proc_loop(Reader, Writer, From) ->  %% Compression loop => get a chunk, compress it, send to writer
    Reader ! {get_chunk, self()},  %% request a chunk from the file reader
    receive
        {chunk, Num, Offset, Data} ->   %% got one, compress and send to writer
            io:format("Chunk ~n"),
            Comp_Data = compress:compress(Data),
            Writer ! {add_chunk, Num, Offset, Comp_Data},
            comp_proc_loop(Reader, Writer, From);
        eof ->  %% end of file, stop reader and writer
            io:format("eof ~n"),
            From ! {eof, self()};
        {error, Reason} ->
            From ! {error, Reason}
    end.

decomp_proc_loop(Reader, Writer, From) ->
    Reader !{get_chunk, self()},
    receive
        {chunk, _Num, Offset, Comp_Data} ->  %% got one
            io:format("Chunk ~n"),
            Data = compress:decompress(Comp_Data),
            Writer ! {write_chunk, Offset, Data},
            decomp_proc_loop(Reader, Writer, From);
        eof ->
            io:format("eof ~n"),
            From ! {eof, self()};
        {error, Reason} ->
            From ! {error, Reason}
    end.

