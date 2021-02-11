-module(comp).

-export([comp/1, comp/2, comp_proc/2, decomp/1, decomp/2, decomp_proc/2, decomp_proc/3]).


-define(DEFAULT_CHUNK_SIZE, 1024*1024).

%%% File Compression

comp(File) -> %% Compress file to file.ch
    comp(File, ?DEFAULT_CHUNK_SIZE).

comp(File, Chunk_Size) ->  %% Starts a reader and a writer which run in separate processes
    case file_service:start_file_reader(File, Chunk_Size) of
        {ok, Reader} ->
            case archive:start_archive_writer(File++".ch") of
                {ok, Writer} ->
                    comp_loop(Reader, Writer);
                {error, Reason} ->
                    io:format("Could not open output file: ~w~n", [Reason])
            end;
        {error, Reason} ->
            io:format("Could not open input file: ~w~n", [Reason])
    end.

comp_loop(Reader, Writer) ->  %% Compression loop => get a chunk, compress it, send to writer
    Reader ! {get_chunk, self()},  %% request a chunk from the file reader
    receive
        {chunk, Num, Offset, Data} ->   %% got one, compress and send to writer
            Comp_Data = compress:compress(Data),
            Writer ! {add_chunk, Num, Offset, Comp_Data},
            comp_loop(Reader, Writer);
        eof ->  %% end of file, stop reader and writer
            Reader ! stop,
            Writer ! stop;
        {error, Reason} ->
            io:format("Error reading input file: ~w~n",[Reason]),
            Reader ! stop,
            Writer ! abort
    end.

%%% Paralel File Compression
comp_proc(File, Procs) -> 
    comp_proc(File, Procs, ?DEFAULT_CHUNK_SIZE).

comp_proc(File, Procs, Chunk_Size) ->
    case file_service:start_file_reader(File, Chunk_Size) of
        {ok, Reader} ->
            case archive:start_archive_writer(File++".ch") of
                {ok, Writer} ->
                    F = fun() -> spawn_link(process,comp_proc_loop,[Reader, Writer,self()]) end,
                    repeat(F, Reader, Writer, [], Procs);
                {error, Reason} ->
                    io:format("Could not open output file: ~w~n", [Reason])
            end;
        {error, Reason} ->
                    io:format("Could not open input file: ~w~n", [Reason])
    end.
%%% Paralel File Decompression
decomp_proc(Archive, Procs) ->
    decomp_proc(Archive, string:replace(Archive, ".ch", "", trailing), Procs).

decomp_proc(Archive, Output_File, Procs) ->
    case archive:start_archive_reader(Archive) of
        {ok, Reader} ->
            case file_service:start_file_writer(Output_File) of
                {ok, Writer} ->
                    F = fun() -> spawn_link(process,decomp_proc_loop,[Reader, Writer,self()]) end,
                    repeat(F, Reader, Writer, [], Procs);
                {error, Reason} ->
                    io:format("Could not open output file: ~w~n", [Reason])
            end;
        {error, Reason} ->
            io:format("Could not open input file: ~w~n", [Reason])
    end.


%%% File Decompression

decomp(Archive) ->
    decomp(Archive, string:replace(Archive, ".ch", "", trailing)).

decomp(Archive, Output_File) ->
    case archive:start_archive_reader(Archive) of
        {ok, Reader} ->
            case file_service:start_file_writer(Output_File) of
                {ok, Writer} ->
                    decomp_loop(Reader, Writer);
                {error, Reason} ->
                    io:format("Could not open output file: ~w~n", [Reason])
            end;
        {error, Reason} ->
            io:format("Could not open input file: ~w~n", [Reason])
    end.

decomp_loop(Reader, Writer) ->
    Reader ! {get_chunk, self()},  %% request a chunk from the reader
    receive
        {chunk, _Num, Offset, Comp_Data} ->  %% got one
            Data = compress:decompress(Comp_Data),
            Writer ! {write_chunk, Offset, Data},
            decomp_loop(Reader, Writer);
        eof ->    %% end of file => exit decompression
            Reader ! stop,
            Writer ! stop;
        {error, Reason} ->
            io:format("Error reading input file: ~w~n", [Reason]),
            Writer ! abort,
            Reader ! stop
    end.

%% REPEAT OPERATION

repeat(F, Reader, Writer, Pids, N) ->
    if  N > 0 ->
        io:format("New process ~n"),
	    repeat(F, Reader, Writer, [F()|Pids], N-1);
	true ->
        io:format("Waiting... ~n"),
	    wait_to_stop(Pids, Reader, Writer)
    end.

wait_to_stop([], Reader, Writer) ->
    io:format("Finish ~n"),
    Reader ! stop,
    Writer ! stop;
wait_to_stop(Pids, Reader, Writer) ->
    receive
        {eof, Pid} ->
            io:format("Deleting process ~n"),
            wait_to_stop(lists:delete(Pid, Pids), Reader, Writer)
    end.