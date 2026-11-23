#!/usr/bin/env python3
"""Inspect only library UI; fixtures live in unique disposable app-container folders."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--derived-data', required=True)
parser.add_argument('--result-bundle', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
base = Path.home() / 'Library/Containers/com.ch563.oralo.mac.dev/Data/Library/Application Support/OraloMacUITests'
environment = os.environ.copy()
created = []
try:
    for language in ['ZH', 'EN']:
        chinese = language == 'ZH'
        identifier = str(uuid.uuid4()).upper()
        directory = base / identifier
        directory.mkdir(parents=True, exist_ok=False)
        created.append(directory)
        mixed = '今天我们总结客户反馈，完善产品计划并提升团队交付质量。Next, we will refine the roadmap and delivery milestones. ' * 300
        english = 'Today I want to share our progress, what we learned from customers, and our next steps for the quarter. ' * 400
        examples = [
            ('团队季度汇报' if chinese else 'Quarterly report', '大家好，今天汇报本季度的团队进展。本季度收入增长18%，交付周期缩短到12天。接下来，我们继续夯实基础，完善 roadmap。下一步，明确每个 milestone 的负责人。'),
            ('2026 年第四季度团队复盘与明年产品规划：交付质量、客户反馈和跨部门协作的详细报告' if chinese else 'Quarterly team review and product planning: delivery quality, customer feedback, and our cross-functional priorities for next year', mixed),
            ('年度战略说明与产品路线图的完整演讲稿：从当前挑战到下一阶段的执行计划' if chinese else "The complete presentation for our annual strategy and product roadmap, from today's challenges to the next stage of execution", english),
            ('尚未写正文的讲稿' if chinese else 'An empty draft', '')
        ]
        date = (datetime.now(timezone.utc) - datetime(2001, 1, 1, tzinfo=timezone.utc)).total_seconds()
        documents = []
        for index, (title, text) in enumerate(examples):
            segments = [{'id': str(uuid.uuid4()), 'text': text, 'pauseAfter': False, 'separatorAfter': ''}] if text else []
            documents.append(dict(id=str(uuid.uuid4()), title=title, text=text, segments=segments,
                hasCustomLayout=False, layoutNeedsReview=False, pronunciations=[], localeID='zh-CN' if chinese else 'en-US',
                revision=1, createdAt=date-index, updatedAt=date-index))
        (directory/'library.json').write_text(json.dumps(dict(schemaVersion=2, documents=documents)), encoding='utf-8')
        environment['TEST_RUNNER_ORALO_LAYOUT_LIBRARY_' + language] = identifier
    subprocess.run(['caffeinate', '-d', '-i', 'xcodebuild', '-project', str(root/'OraloMac.xcodeproj'),
        '-scheme', 'OraloMac', '-configuration', 'Debug', '-destination', 'platform=macOS,arch=arm64',
        '-derivedDataPath', args.derived_data, '-resultBundlePath', args.result_bundle, '-parallel-testing-enabled', 'NO',
        '-only-testing:OraloMacUITests/LibraryLayoutUITests/testLibraryCardsAndRowsAcrossLanguagesAndAppearances',
        'ONLY_ACTIVE_ARCH=YES', 'ARCHS=arm64', 'test'], env=environment, check=True)
finally:
    for directory in created:
        shutil.rmtree(directory)
