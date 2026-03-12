import pydot
import networkx as nx
import re
import sys
# —————————————————————————————————————
# 1) Utility: 주어진 subgraph 안의 노드/엣지/레이블 재귀 수집
def collect_cfg(sg):
    nodes, edges, labels = set(), [], {}
    # 1. 이 서브그래프 자체의 노드·엣지
    for n in sg.get_nodes():
        name = n.get_name().strip('"')
        if "_basic_block_" in name:
            nodes.add(name)
            # 1) 따옴표 제거, 2) DOT escape문자('\') 제거
            raw = n.get_attributes().get("label", "")
            lbl = raw.strip('"').replace('\\', '')
            labels[name] = lbl
    for e in sg.get_edges():
        src = e.get_source().strip('"').split(':')[0]
        dst = e.get_destination().strip('"').split(':')[0]
        edges.append((src, dst))
    # 2. 자식 subgraph(예: loop cluster) 재귀
    for child in sg.get_subgraphs():
        n2, e2, l2 = collect_cfg(child)
        nodes |= n2
        edges += e2
        labels.update(l2)
    return nodes, edges, labels

# —————————————————————————————————————
# 2) DOT 파일 로드 및 함수별 cluster 추출
dot_path = sys.argv[1]
graphs = pydot.graph_from_dot_file(dot_path)
dot = graphs[0]

func_clusters = {}
for sg in dot.get_subgraphs():
    lbl = sg.get_attributes().get("label")
    if not lbl:
        continue
    label = lbl.strip('"')
    # label이 "foo ()" 형식인지 확인
    m = re.fullmatch(r'(.+)\s*\(\)', label)
    if not m:
        continue
    func = m.group(1).strip()          # 예: "main", "find", "printf"
    nodes, edges, labels = collect_cfg(sg)
    func_clusters[func] = {
        "nodes": nodes,
        "edges": edges,
        "labels": labels
    }

# —————————————————————————————————————
# 3) 각 함수의 intra-procedural max_depth 계산
intra_depth = {}
for func, data in func_clusters.items():
    G = nx.DiGraph()
    G.add_nodes_from(data["nodes"])
    G.add_edges_from(data["edges"])
    C = nx.condensation(G)   # 사이클 묶어서 DAG로 변환
    # SCC당 블록 수를 weight로 설정
    weights = {cid: len(members) for cid, members in C.nodes(data="members")}
    nx.set_node_attributes(C, weights, name="weight")
    if len(C):
        intra_depth[func] = nx.dag_longest_path_length(C, weight="weight")
    else:
        intra_depth[func] = 0

# —————————————————————————————————————
# 4) 호출 그래프(call graph) 구성 (수정판)
callG = nx.DiGraph()
callG.add_nodes_from(func_clusters.keys())

# 4-1) 레이블에서 escape를 제거했으니, 단순히 “funcName(” 형태로 탐지
func_names = list(func_clusters.keys())
name_pattern = '|'.join(re.escape(fn) for fn in func_names)
pattern = re.compile(r'\b(' + name_pattern + r')\s*\(')


# 4-2) escape 제거된 레이블에서 호출을 탐지
for func, data in func_clusters.items():
    for lbl in data["labels"].values():
        for mm in pattern.finditer(lbl):
            callee = mm.group(1)
            if callee != func:
                callG.add_edge(func, callee)
# —————————————————————————————————————
# 5) 인터프로시절(interprocedural) max_depth 계산 – node→edge weights 변환
CG = nx.condensation(callG)

#   a) 각 supernode 의 weight = 그 안의 함수들의 intra_depth 합
super_w = {
    comp: sum(intra_depth[f] for f in members)
    for comp, members in CG.nodes(data="members")
}
nx.set_node_attributes(CG, super_w, name="node_weight")

#   b) main 이 속한 컴포넌트
mapping = CG.graph["mapping"]       # e.g. { "main": 3, "find": 5, ... }
main_comp = mapping["main"]

#   c) main 부터 닿을 수 있는 부분만 뽑아서 subgraph
reach = set(nx.descendants(CG, main_comp)) | {main_comp}
subG = CG.subgraph(reach).copy()

#   d) **엣지**마다 weight = dest node_weight 으로 설정
for u, v in subG.edges():
    subG[u][v]['weight'] = super_w[v]

#   e) 엣지 가중치의 최장 경로 길이 (합산)
#      이 값은 main_comp 제외한 나머지 경로상의 node depths 의 합입니다.
edge_sum = nx.dag_longest_path_length(subG, weight='weight')

#   f) 마지막으로 main_comp 의 depth 를 더해 줍니다.
inter_depth = super_w[main_comp] + edge_sum
print(inter_depth)
