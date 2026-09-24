import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// 替换为第二步得到的图片目录 CID，只填 CID，不要填 ipfs:// 或网址。
const imageCID = "bafybeifmrz22k355ljr4lcndh4qsrshmtpgipbdo2wbnxsfgw4kjcttycy";
// 先生成 tokenId 0、1、2；正式使用时必须与合约 maxSupply 一致。
const maxSupply = 1;

if (!/^(Qm[1-9A-HJ-NP-Za-km-z]{44}|bafy[a-z2-7]+)$/.test(imageCID)) {
  throw new Error("请先把 imageCID 替换为 Pinata 返回的完整图片目录 CID");
}
if (!Number.isSafeInteger(maxSupply) || maxSupply <= 0) {
  throw new Error("maxSupply 必须是正整数");
}

const output = join(process.cwd(), "nft-assets", "metadata");
mkdirSync(output, { recursive: true });
const save = (file, data) =>
  writeFileSync(file, JSON.stringify(data, null, 2) + "\n", "utf8");

save(join(output, "blindbox.json"), {
  name: "神秘盲盒",
  description: "等待揭示后查看你的 NFT！",
  image: `ipfs://${imageCID}/blindbox.png`,
  attributes: [],
});

const rarities = [
  ["common", "Common", "普通英雄"],
  ["rare", "Rare", "稀有英雄"],
  ["epic", "Epic", "史诗英雄"],
  ["legendary", "Legendary", "传说英雄"],
];

for (const [folder, rarity, label] of rarities) {
  const directory = join(output, folder);
  mkdirSync(directory, { recursive: true });
  for (let tokenId = 0; tokenId < maxSupply; tokenId++) {
    save(join(directory, `${tokenId}.json`), {
      name: `${label} #${tokenId}`,
      description: "NFT 盲盒课程练习作品",
      image: `ipfs://${imageCID}/${folder}.png`,
      attributes: [{ trait_type: "Rarity", value: rarity }],
    });
  }
}
console.log(`已生成 ${4 * maxSupply + 1} 个 JSON 文件：${output}`);
