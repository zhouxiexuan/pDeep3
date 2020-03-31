param (
    [switch]$rescore = $false,
    [switch]$export = $false,
    [switch]$use_window = $false,
    [switch]$tune = $false,
    [switch]$ipf = $false,
    [switch]$cache_disk = $false,
    [string]$temp = 'E:/temp'
    [switch]$subsample = $false,
    [string]$raw_dir = $(throw "-raw_dir is required."),
    [string]$output_dir = $(throw "-output_dir is required."),
    [string]$lib = "e:/DIATools/openswath/library/pDeep/phl_pDeep_QE27.pqp",
    [string]$irt = "e:/DIATools/openswath/library/pDeep/cell_RT_proteins_fasta_QE27.tsv"
)

If ($cache_disk)
{
    $cache='cache'
}
else
{
    $cache='normal' #normal, cache, cacheWorkingInMemory, workingInMemory
}

$global:win="e:\DIAData\Specter\HEK_SpikeP100\DIAwindow.txt"
$global:win_left="e:\DIAData\Specter\HEK_SpikeP100\DIAwindow-left.txt"
$global:win_right="e:\DIAData\Specter\HEK_SpikeP100\DIAwindow-right.txt"



$ms1_tol_type='ppm' # or 'Th'
$ms1_tol=10
$ms2_tol_type='ppm' # or 'Th'
$ms2_tol=20
$batch=5000
$thread=6
$overlapDIA='false'

# if (!(Test-Path $lib -PathType leaf))
# {
    # Write-Host "========== Converting to PQP =========="
    # $pqp=-join($lib.substring(0, $lib.Length-3), 'pqp')
    # TargetedFileConverter -in $lib -out $pqp -threads 4
    # Write-Host "========== Generating decoy =========="
    # OpenSWATHDecoyGenerator -in $pqp -out $lib -method reverse -threads 4
# }

function run_one($raw, $out)
{
    Write-Host $raw
    OpenSwathWorkflow -in $raw -tr $lib -sort_swath_maps -readOptions $cache -tempDirectory $temp -batchSize $batch -out_osw $out -threads $thread -tr_irt $irt -rt_extraction_window 600 -mz_extraction_window_unit $ms2_tol_type -mz_extraction_window $ms2_tol -mz_extraction_window_ms1_unit $ms1_tol_type -mz_extraction_window_ms1 $ms1_tol -matching_window_only $overlapDIA -min_coverage 0.01 -min_rsq 0.95 -force
    # OpenSwathWorkflow '-in' $raw -tr $lib -sort_swath_maps -readOptions cache -tempDirectory E:/Temp -batchSize 10000 -swath_windows_file $global:win -tr_irt $irt -out_osw $out -threads 4 -use_ms1_traces -enable_uis_scoring
    
    # no matter -use_ms1_traces or not, precursor ion will be matched in ms1? But if -use_ms1_traces, ms1 features will be used in scoring
}

function run_one_window($raw, $out)
{
    Write-Host $raw
    OpenSwathWorkflow -in $raw -tr $lib -sort_swath_maps -readOptions $cache -tempDirectory $temp -batchSize $batch -out_osw $out -threads $thread -tr_irt $irt -rt_extraction_window 600 -mz_extraction_window_unit $ms2_tol_type -mz_extraction_window $ms2_tol -mz_extraction_window_ms1_unit $ms1_tol_type -mz_extraction_window_ms1 $ms1_tol -matching_window_only $overlapDIA -min_coverage 0.01 -min_rsq 0.95 -swath_windows_file $global:win -force -use_ms1_traces -enable_uis_scoring
    # OpenSwathWorkflow '-in' $raw -tr $lib -sort_swath_maps -readOptions cache -tempDirectory E:/Temp -batchSize 10000 -swath_windows_file $global:win -tr_irt $irt -out_osw $out -threads 4 -use_ms1_traces
    
    # no matter -use_ms1_traces or not, precursor ion will be matched in ms1? But if -use_ms1_traces, ms1 features will be used in scoring
}

function run_pyprophet($output_dir, $sample_ratio=0)
{   
    Write-Host "========== Run PyProphet =========="
    Set-Location -Path $output_dir
    $tmpl=-join("--template=", $lib)
    $osw_files = Get-ChildItem -Path . -Recurse -Include raw*.osw
    $sub_files = @()
    
    Foreach ($run in $osw_files)
    {
        $bak=-join($run,'.bak')
        Copy-Item -Path $run $bak
    }
    
    if (($sample_ratio -eq 0) -or ($sample_ratio -eq 1))
    {
        pyprophet merge $tmpl --out=score.model $osw_files
    }
    else
    {
        Write-Host "========== Sub-sampling =========="
        Write-Host "Sub-sample ratio =", $sample_ratio
        Foreach ($run in $osw_files)
        {
            pyprophet subsample --in=$run --out=${run}.sub --subsample_ratio=$sample_ratio
            $sub_files += -join($run, '.sub')
        }
        pyprophet merge $tmpl --out=score.model $sub_files
        Write-Host $sub_files
    }
    
    Write-Host "========== Scoring =========="
    pyprophet score --in=score.model --level=ms1 score --in=score.model --level=ms2
    Foreach ($run in $osw_files)
    {
        pyprophet score --in=$run --apply_weights=score.model --level=ms2
        pyprophet ipf --in=$run
    }
    
    Write-Host "========== Reducing =========="
    $reduced_files = @()
    Foreach ($run in $osw_files)
    {
        $run_reduced = -join(${run},".reduce") # generates .oswr files
        pyprophet reduce --in=$run --out=$run_reduced
        $reduced_files += $run_reduced
    }
        
    Write-Host "========== Estimating FDR =========="
    pyprophet merge --template=score.model --out=global_fdr.model $reduced_files
    pyprophet peptide --context=global --in=global_fdr.model
    pyprophet protein --context=global --in=global_fdr.model
    
    Foreach ($run in $osw_files)
    {
        pyprophet backpropagate --in=$run --apply_scores=global_fdr.model
    }
}


function run_pyprophet_ipf($output_dir)
{   
    Write-Host "========== Run PyProphet (IPF) =========="
    Set-Location -Path $output_dir
    $osw_files = Get-ChildItem -Path . -Recurse -Include raw*.osw
    
    Foreach ($run in $osw_files)
    {
        Copy-Item -Path $run ${run}.bak
    }
    pyprophet merge --template=$lib --out=score.model $osw_files
    
    Write-Host "========== Scoring =========="
    pyprophet score --in=score.model --level=ms2 
    # pyprophet score --in=score.model --level=ms1 
    pyprophet score --in=score.model --level=transition
    pyprophet ipf --in=score.model
    # Foreach ($run in $osw_files)
    # {
        # pyprophet score --in=$run --apply_weights=score.model --level=ms2 
        # pyprophet score --in=$run --apply_weights=score.model --level=ms1 
        # pyprophet score --in=$run --apply_weights=score.model --level=transition
    # }
    
    # Write-Host "========== Reducing =========="
    # $reduced_files = @()
    # Foreach ($run in $osw_files)
    # {
        # $run_reduced = -join(${run},".reduce") # generates .oswr files
        # pyprophet reduce --in=$run --out=$run_reduced
        # $reduced_files += $run_reduced
    # }
        
    Write-Host "========== Estimating FDR =========="
    # pyprophet merge --template=score.model --out=global_fdr.model $reduced_files
    pyprophet peptide --context=global --in=score.model
    pyprophet protein --context=global --in=score.model
    
    Foreach ($run in $osw_files)
    {
        pyprophet backpropagate --in=$run --apply_scores=score.model
    }
}

if ($export)
{
    $osw_files = Get-ChildItem -Path $output_dir -Recurse -Include raw*.osw
    Write-Host $osw_files
    Foreach ($run in $osw_files)
    {
        Write-Host "pyprophet export --in=$run --out=${run}.tsv --format=legacy_merged"
        pyprophet export --in=$run --out=${run}.tsv --format=legacy_merged
    }
}
else
{
    New-Item -Path $output_dir -ItemType Directory
    Remove-Item ${output_dir}/*.sub
    Remove-Item ${output_dir}/*.reduce
    Remove-Item ${output_dir}/*.model

    $raw_files = Get-ChildItem -Path $raw_dir -Recurse -Include *.mzML
    Write-Host $raw_files
    $i = 1
    if ($rescore)
    {
        Foreach ($raw in $raw_files)
        {
            If ($use_window)
            {
                Move-Item -Path ${output_dir}/raw${i}.left.osw.bak -Destination ${output_dir}/raw${i}.left.osw -Force
                
                Move-Item -Path ${output_dir}/raw${i}.right.osw.bak -Destination ${output_dir}/raw${i}.right.osw -Force
            }
            else
            {
                Move-Item -Path ${output_dir}/raw${i}.osw.bak -Destination ${output_dir}/raw${i}.osw -Force
            }
            $i++
        }
    }
    else
    {
        Foreach ($raw in $raw_files)
        {
            If ($use_window)
            {
                # run_one_window $raw $out_path
                $global:win=$global:win_left
                $out_path=Join-Path -Path $output_dir -ChildPath raw${i}.left.osw
                run_one_window $raw $out_path
                
                $global:win=$global:win_right
                $out_path=Join-Path -Path $output_dir -ChildPath raw${i}.right.osw
                run_one_window $raw $out_path
            }
            else
            {
                $out_path=Join-Path -Path $output_dir -ChildPath raw${i}.osw
                run_one $raw $out_path
            }
            if ($tune) { break }
            $i++
        }
        # $temp=Join-Path -Path $temp -ChildPath *
        if ($cache -eq 'cache') { Remove-Item -Path ${temp}/*.* }
    }

    if ($use_window -and $subsample) { $sample_ratio=1/(@($raw_files).Length)/2 }
    elseif ($subsample) { $sample_ratio=1/(@($raw_files).Length) }
    else { $sample_ratio = 1 }
    if ($ipf) {run_pyprophet_ipf $output_dir}
    else {run_pyprophet $output_dir $sample_ratio}
}


