#!/usr/bin/env nextflow

//
// Demultiplex Illumina BCL data using bcl-convert
//

include { BCLCONVERT } from "../../../modules/nf-core/modules/bclconvert/main"
include { UNTAR      } from "../../../modules/nf-core/modules/untar/main"

workflow DEMULTIPLEX {
    take:
        ch_flowcell // [[id:"", lane:""],samplesheet.csv, path/to/bcl/files]

    main:
        ch_versions = Channel.empty()

        // Split flowcells into separate channels containg run as tar and run as path
        // https://nextflow.slack.com/archives/C02T98A23U7/p1650963988498929
        ch_flowcell
            .branch { meta, samplesheet, run ->
                tar: run.toString().endsWith(".tar.gz")
                dir: true
            }.set { ch_flowcells }

        ch_flowcells.tar
            .multiMap { meta, samplesheet, run ->
                samplesheets: [ meta, samplesheet ]
                run_dirs: [ meta, run ]
            }.set { ch_flowcells_tar }

        // MODULE: untar
        // Runs when run_dir is a tar archive
        // Re-join the metadata and the untarred run directory with the samplesheet
        ch_flowcells_tar_merged = ch_flowcells_tar.samplesheets.join( UNTAR ( ch_flowcells_tar.run_dirs ).untar )
        ch_versions = ch_versions.mix(UNTAR.out.versions)

        // Merge the two channels back together
        ch_flowcells = ch_flowcells.dir.mix(ch_flowcells_tar_merged)

        // MODULE: bclconvert
        // Demultiplex the bcl files
        BCLCONVERT( ch_flowcells)
        ch_versions = ch_versions.mix(BCLCONVERT.out.versions)

        // Genereate meta for each fastq
        ch_bclconvert_fastq = generate_fastq_meta(BCLCONVERT.out.fastq)

    emit:
        bclconvert_fastq    = ch_bclconvert_fastq
        bclconvert_reports  = BCLCONVERT.out.reports
        bclconvert_interop  = BCLCONVERT.out.interop
        versions            = ch_versions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

// Add meta values to fastq channel
def generate_fastq_meta(ch_reads) {
    ch_reads.map {
        fc_meta, raw_fastq ->
        raw_fastq
    }
    // Create a tuple with the meta.id and the fastq
    .flatten().map{
        fastq ->
        def meta = [
            "id": fastq.getSimpleName().toString() - ~/_R[0-9]_001.*$/,
            "samplename": fastq.getSimpleName().toString() - ~/_S[0-9]+.*$/
        ]
        [ meta , fastq ]
    }
    // Group by meta.id for PE samples
    .groupTuple(by: [0])
    // Add meta.single_end
    .map {
        meta, fastq ->
        if (fastq.size() == 1){
            meta.single_end = true
        } else {
            meta.single_end = false
        }
        return [ meta, fastq.flatten() ]
    }
}
