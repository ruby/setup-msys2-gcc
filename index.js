// Copyright (c) 2020-2022 MSP-Greg

'use strict';

const fs          = require('fs')
const core        = require('@actions/core')
const { Octokit } = require('@octokit/rest')
const { retry }   = require('@octokit/plugin-retry')

const tarExt = '.7z'

// returns updated release body
const updateBody = (releaseBody, releaseName) => {
  const re = new RegExp('^\\*\\*' + releaseName + ':\\*\\* ([^\\r]+)', 'm')
  // (match, p1, p2, offset, str)
  return releaseBody.replace(re, () => `**${releaseName}:** gcc package   Run No: ${process.env.GITHUB_RUN_NUMBER}`)
}

const run = async () => {
  try {

    const releaseTag  = core.getInput('release_tag' , { required: true });
    const releaseName = core.getInput('release_name', { required: true });

    const gccTar = `${releaseName}${tarExt}`

    // application/x-7z-compressed  application/octet-stream
    const assetContentType = 'application/x-7z-compressed'

    // Get owner and repo from context of payload that triggered the action
    const [ owner, repo ] = process.env.GITHUB_REPOSITORY.split('/')

    const MyOctokit = Octokit.plugin(retry)

    const octokit = new MyOctokit({
      auth: process.env.GITHUB_TOKEN,
      userAgent: `${owner}--${repo}`,
      timeZone: 'America/Chicago'
    })

    // Get releaseId and uploadUrl needed for asset processing
    const { data: { id: releaseId, upload_url: uploadUrl }
    } = await octokit.repos.getReleaseByTag({
      owner: owner,
      repo: repo,
      tag: releaseTag
    })

    const releases = await octokit.repos.listReleaseAssets({
      owner: owner,
      repo: repo,
      release_id: releaseId
    })
    // console.log(releases);

    let assets = new Map()

    releases.data.forEach(e => assets.set(e.name, e.id))

    const releaseIdOld = assets.get(gccTar)

    // release shouldn't exist, for cleaning
    const releaseIdNewBad = assets.get(`new-${gccTar}`)
    if ( releaseIdNewBad) {
      console.log('  Delete bad new')
      await octokit.repos.deleteReleaseAsset({
        owner: owner,
        repo: repo,
        asset_id: releaseIdNewBad
      })
    }

    // Setup headers for API call
    const headers = {
      'content-type': assetContentType,
      'content-length': fs.statSync(gccTar).size
    }

    console.time('  Upload 7z')

    // Upload ruby file, use prefix 'new-', rename later
    // https://developer.github.com/v3/repos/releases/#upload-a-release-asset
    // https://octokit.github.io/rest.js/v17#repos-upload-release-asset
    let fileData = fs.readFileSync(gccTar)
    const { data: { id: releaseIdNew }
    } = await octokit.repos.uploadReleaseAsset({
      url: uploadUrl,
      headers,
      name: `new-${gccTar}`,
      data: fileData
    })
    fileData = null

    console.timeEnd('  Upload 7z')

    // wait for file processing
    await new Promise(r => setTimeout(r, 10000))

    console.time('    Replace')

    if (releaseIdOld) {
      console.log(' rename current to old')
      await octokit.repos.updateReleaseAsset({
        owner: owner,
        repo: repo,
        asset_id: releaseIdOld,
        name: `old-${gccTar}`
      })
    }

    console.log(' rename new to current')
    await octokit.repos.updateReleaseAsset({
      owner: owner,
      repo: repo,
      asset_id: releaseIdNew,
      name: gccTar
    })

    console.timeEnd('    Replace')

    // wait for file processing
    await new Promise(r => setTimeout(r, 5000))

    if (releaseIdOld) {
      console.log(' delete old')
      await octokit.repos.deleteReleaseAsset({
        owner: owner,
        repo: repo,
        asset_id: releaseIdOld
      })
    }

    console.time('Update Info')

    // Get Release body
    const {data: { body: releaseBody }
    } = await octokit.repos.getReleaseByTag({
      owner: owner,
      repo: repo,
      tag: releaseTag
    })

    // Update Release body
    // https://octokit.github.io/rest.js/v18#repos-update-release-asset
    await octokit.repos.updateRelease({
      owner: owner,
      repo: repo,
      release_id: releaseId,
      body: updateBody(releaseBody, releaseName)
    })

    console.timeEnd('Update Info')

  } catch (error) {
    core.setFailed(error.message)
  }
}

run()
